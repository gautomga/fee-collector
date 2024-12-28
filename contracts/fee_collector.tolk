tolk 0.6

import "@stdlib/common.tolk"
import "@stdlib/gas-payments.tolk"

const ERROR_TAX_BPS_EXCEEDS_MAXIMUM = 1100;
const ERROR_PAYLOAD_IS_REQUIRED = 1101;
const ERROR_OPERATOR_UNAUTHORIZED = 1102;

const ERROR_UNKNONW_OP = 65535;

fun loadContractData(): (slice) {
    var ds = getContractData().beginParse();
    val operatorAddress = ds.loadAddress();
    ds.assertEndOfSlice();
    return (operatorAddress);
}

const MINIMAL_BALANCE = 100000000; // 0.1 TON

const MAX_TAX_BPS = 10000;

const TRANSFER_OP = 0x0f8a7ea5;
const TRANSFER_NOTIFICATION_OP = 0x7362d09c;
const PAYOUT_OP = 0x474f86cf;

const CLAIM_JETTON_OP = 2;
const CLAIM_TON_OP = 3;

@pure
fun loadTaxBPS(mutate self: slice): int
    asm( -> 1 0) "16 LDU";

@pure
fun getMyStoragePaidPayment(): int asm "STORAGEFEES";

// transfer#0f8a7ea5 query_id:uint64 amount:(VarUInteger 16) destination:MsgAddress
//                   response_destination:MsgAddress custom_payload:(Maybe ^Cell)
//                   forward_ton_amount:(VarUInteger 16) forward_payload:(Either Cell ^Cell)
//                   = InternalMsgBody;

@inline
fun transfer_packMessage(
    queryId: int,
    amount: int,
    destination: slice,
    responseDestination: slice,
    customPayload: cell,
    forwardAmount: int,
    eitherForwardPayload: builder
): builder {
    return beginCell()
        .storeMessageOp(TRANSFER_OP)
        .storeMessageQueryId(queryId)
        .storeCoins(amount)
        .storeSlice(destination)
        .storeSlice(responseDestination)
        .storeMaybeRef(customPayload)
        .storeCoins(forwardAmount)
        .storeBuilder(eitherForwardPayload);
}


@inline
fun sendSimpleMessage(flags: int, destination: slice, value: int, body: builder, mode: int): int {
    var msg: cell = beginCell()
    .storeUint(flags, 6)
    .storeSlice(destination)
    .storeCoins(value)
    .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
    .storeBuilder(body)
    .endCell();

    return sendMessage(msg, mode);
}

fun onInternalMessage(myBalance: int, msgValue: int, msgFull: cell, msgBody: slice) {
    if (!msgBody.getRemainingBitsCount()) {
        return;
    }

    var cs = msgFull.beginParse();
    val flags = cs.loadMessageFlags();
    val senderAddress = cs.loadAddress();

    // ignore both empty and bounced messages
    if (isMessageBounced(flags)) {
        return;
    }

    val op = msgBody.loadMessageOp();
    val queryId = msgBody.loadMessageQueryId();

    // transfer_notification#7362d09c query_id:uint64 amount:(VarUInteger 16)
    //                                sender:MsgAddress forward_payload:(Either Cell ^Cell)
    //                                = InternalMsgBody;
    if (op == TRANSFER_NOTIFICATION_OP) {
        val amount: int = msgBody.loadCoins();
        msgBody.loadAddress(); // NOTE: It isn't important who sent jettons. Just skip it.
        var forwardPayload: slice = msgBody.loadBool()
            ? msgBody.loadRef().beginParse()
            : msgBody;

        // forward_payload#_ recipientAddress:MsgAddressInt taxBPS:uint16 = ForwardPayload;
        val recipientAddress = forwardPayload.loadAddress();
        val taxBPS = forwardPayload.loadTaxBPS();
        assert(taxBPS <= MAX_TAX_BPS) throw ERROR_TAX_BPS_EXCEEDS_MAXIMUM;

        val heldFee = mulDivFloor(amount, taxBPS, MAX_TAX_BPS);

        reserveToncoinsOnBalance(
            getMyStoragePaidPayment() + getMyStorageDuePayment(),
            RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE
        );

        sendSimpleMessage(
            BOUNCEABLE,
            senderAddress,
            0,
            transfer_packMessage(
                queryId,
                amount - heldFee,
                recipientAddress,
                recipientAddress,
                null,
                0,
                beginCell().storeBool(false)
            ),
            SEND_MODE_CARRY_ALL_BALANCE
        );

        return;
    }

    // payout#474f86cf query_id:uint64 payload:(Maybe ^Cell) = InMsgBody;
    if (op == PAYOUT_OP) {
        val payload: cell = msgBody.loadMaybeRef();
        assert(payload != null) throw ERROR_PAYLOAD_IS_REQUIRED;

        var forwardPayload = payload.beginParse();
        // forward_payload#_ recipientAddress:MsgAddressInt taxBPS:uint16 = ForwardPayload;
        val recipientAddress = forwardPayload.loadAddress();
        val taxBPS = forwardPayload.loadTaxBPS();

        val heldFee = mulDivFloor(msgValue, taxBPS, MAX_TAX_BPS);

        reserveToncoinsOnBalance(
            (myBalance - msgValue) + heldFee + getMyStoragePaidPayment() + getMyStorageDuePayment(),
            RESERVE_MODE_EXACT_AMOUNT
        );

        sendSimpleMessage(
            BOUNCEABLE,
            senderAddress,
            0,
            beginCell(),
            SEND_MODE_CARRY_ALL_BALANCE
        );

        return;
    }

    if (op == CLAIM_JETTON_OP) {
        val (operatorAddress: slice) = loadContractData();
        assert(isSliceBitsEqual(senderAddress, operatorAddress)) throw ERROR_OPERATOR_UNAUTHORIZED;

        val walletAddress: slice = msgBody.loadAddress();
        val recipientAddress: slice = msgBody.loadAddress();
        val amount: int = msgBody.loadCoins();

        reserveToncoinsOnBalance(
            getMyStoragePaidPayment() + getMyStorageDuePayment(),
            RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE
        );

        sendSimpleMessage(
            BOUNCEABLE,
            walletAddress,
            0,
            transfer_packMessage(
                queryId,
                amount,
                recipientAddress,
                senderAddress,
                null,
                0,
                beginCell().storeBool(false)
            ),
            SEND_MODE_CARRY_ALL_BALANCE
        );

        return;
    }

    if (op == CLAIM_TON_OP) {
        val (operatorAddress: slice) = loadContractData();
        assert(isSliceBitsEqual(senderAddress, operatorAddress)) throw ERROR_OPERATOR_UNAUTHORIZED;

        val recipientAddress: slice = msgBody.loadAddress();
        val payload: slice = msgBody;

        reserveToncoinsOnBalance(MINIMAL_BALANCE, RESERVE_MODE_AT_MOST);
        sendSimpleMessage(
            NON_BOUNCEABLE,
            recipientAddress,
            0,
            beginCell().storeBuilder(payload),
            SEND_MODE_CARRY_ALL_BALANCE
        );

        return;
    }

    throw ERROR_UNKNONW_OP;
}
