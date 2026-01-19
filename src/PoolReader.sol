// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract PoolReader {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    // Frontend sẽ gọi hàm này
    function getSlot0(PoolKey calldata key) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    ) {
        // Chuyển Key -> ID -> Gọi StateLibrary qua extload
        return manager.getSlot0(key.toId());
    }

    // Lấy thanh khoản
    function getLiquidity(PoolKey calldata key) external view returns (uint128 liquidity) {
        return manager.getLiquidity(key.toId());
    }
}