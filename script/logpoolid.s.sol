// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import "forge-std/console2.sol";

contract CalculatePoolId is Script {
    using PoolIdLibrary for PoolKey;

    // --- CẤU HÌNH INPUT CỦA BẠN ---
    address constant TOKEN_A = 0x40f29eBAbF560965ABA3A1b3c41d68B3FBD3C6D8;
    address constant TOKEN_B = 0x81BBA474F7BFe1DC04aD2a085c884ED76B55fB5D;
    address constant HOOK    = 0xfBab02f7cf8c284321eD0A0bb4D64ce0EB877fc0;
    
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() public pure {
        // 1. Tự động sắp xếp Token0 và Token1 (Quan trọng!)
        // Logic: Địa chỉ nhỏ hơn làm Token0
        Currency currency0;
        Currency currency1;

        if (TOKEN_A < TOKEN_B) {
            currency0 = Currency.wrap(TOKEN_A);
            currency1 = Currency.wrap(TOKEN_B);
            console2.log("Sorted: Token A is Currency0");
        } else {
            currency0 = Currency.wrap(TOKEN_B);
            currency1 = Currency.wrap(TOKEN_A);
            console2.log("Sorted: Token B is Currency0");
        }

        // 2. Tạo PoolKey struct
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });

        // 3. Tính PoolId bằng thư viện chuẩn
        PoolId id = key.toId();
        
        // 4. Tính thủ công (để verify logic Frontend)
        // Frontend phải encode đúng thứ tự này:
        bytes32 manualId = keccak256(abi.encode(
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            key.hooks
        ));

        // --- IN KẾT QUẢ RA MÀN HÌNH ---
        console2.log("-------------------------------------------");
        console2.log("Currency0:   ", Currency.unwrap(currency0));
        console2.log("Currency1:   ", Currency.unwrap(currency1));
        console2.log("Fee:         ", key.fee);
        console2.log("TickSpacing: ", key.tickSpacing);
        console2.log("Hooks:       ", address(key.hooks));
        console2.log("-------------------------------------------");
        console2.log(">>> POOL ID (Library):");
        console2.logBytes32(PoolId.unwrap(id));
        console2.log("");
        console2.log(">>> POOL ID (Manual Keccak):");
        console2.logBytes32(manualId);
        console2.log("-------------------------------------------");
    }
}