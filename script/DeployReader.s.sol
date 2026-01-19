// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolReader} from "../src/PoolReader.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import "forge-std/console2.sol";

contract DeployReader is Script {
    // Thay địa chỉ PoolManager của bạn vào đây
    address constant MANAGER_ADDRESS = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; 

    function run() public {
        vm.startBroadcast();
        
        PoolReader reader = new PoolReader(IPoolManager(MANAGER_ADDRESS));
        
        console2.log("PoolReader deployed at:", address(reader));
        
        vm.stopBroadcast();
    }
}