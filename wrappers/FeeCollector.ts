import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type FeeCollectorConfig = {};

export function feeCollectorConfigToCell(config: FeeCollectorConfig): Cell {
    return beginCell().endCell();
}

export class FeeCollector implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new FeeCollector(address);
    }

    static createFromConfig(config: FeeCollectorConfig, code: Cell, workchain = 0) {
        const data = feeCollectorConfigToCell(config);
        const init = { code, data };
        return new FeeCollector(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}
