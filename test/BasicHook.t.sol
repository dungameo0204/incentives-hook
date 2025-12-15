// NOTE: This is based on V4PreDeployed.s.sol
// You can make changes to base on V4Deployer.s.sol to deploy everything fresh as well

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BasicHook} from "../src/BasicHook.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import "forge-std/console.sol";

contract BasicHookTest is Test, Deployers {
    BasicHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        address hookAddress = address(flags);
        deployCodeTo("BasicHook.sol", abi.encode(manager), hookAddress);
        hook = BasicHook(hookAddress);

        (key, ) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            hook,
            500,
            SQRT_PRICE_1_1
        );
    }

    function test_removeLiqFees() public {
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -9e17,
                salt: 0
            }),
            ZERO_BYTES
        );
    }
}
