import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Cell, toNano } from '@ton/core';
import { FeeCollector } from '../wrappers/FeeCollector';
import { compile } from '@ton/blueprint';
import '@ton/test-utils';

describe('FeeCollector', () => {
    let code: Cell;

    beforeAll(async () => {
        code = await compile('FeeCollector');
    });

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let feeCollector: SandboxContract<FeeCollector>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        feeCollector = blockchain.openContract(FeeCollector.createFromConfig({}, code));

        deployer = await blockchain.treasury('deployer');

        const deployResult = await feeCollector.sendDeploy(deployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: feeCollector.address,
            deploy: true,
            success: true,
        });
    });

    it.todo('returns operator address');

    describe('receive jetton', () => {
        it.todo('charges fee in jetton');
        it.todo('forwards remaining to recipient_addr');
    });

    describe('receive TON', () => {
        it.todo('charges fee in TON');
        it.todo('forwards remaining to recipient_addr');
    });

    describe('claiming jettons', () => {
        it.todo('fails if sender_address is different from operator_address');
        it.todo('sends a jetton to receiver_addr');
        it.todo('does not send TON to receiver_addr');
    });

    describe('claiming TON', () => {
        it.todo('fails if sender_address is different from operator_address');
        it.todo('sends TON to receiver_addr using payload as body');
        it.todo('keeps MIN_BALANCE after claim');
    });
});
