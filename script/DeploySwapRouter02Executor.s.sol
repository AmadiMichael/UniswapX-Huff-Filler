// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {SwapRouter02Executor} from "uniswapx/src/sample-executors/SwapRouter02Executor.sol";
import {ISwapRouter02} from "uniswapx/src/external/ISwapRouter02.sol";
import {IReactor} from "uniswapx/src/interfaces/IReactor.sol";
import {HuffDeployer} from "foundry-huff/HuffDeployer.sol";

contract DeploySwapRouter02Executor is Script {
    function setUp() public {}

    function run() public returns (SwapRouter02Executor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");

        // IReactor reactor = IReactor(
        //     vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_REACTOR")
        // );
        // address whitelistedCaller = vm.envAddress(
        //     "FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_WHITELISTED_CALLER"
        // );
        address owner = vm.envAddress(
            "FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_OWNER"
        );
        // ISwapRouter02 swapRouter02 = ISwapRouter02(
        //     vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_SWAPROUTER02")
        // );

        vm.startBroadcast(privateKey);
        // executor = new SwapRouter02Executor{salt: 0x00}(
        //     whitelistedCaller,
        //     reactor,
        //     owner,
        //     swapRouter02
        // );

        // Values of `swapRouter02`, `whitelistedCaller` and `reactor` should be filled in `test/HuffWrappers/IntegrationConstantsWrapper.huff` file
        string memory integrationConstantsWrapper = vm.readFile(
            "test/HuffWrappers/IntegrationConstantsWrapper.huff"
        );
        executor = SwapRouter02Executor(
            payable(
                HuffDeployer
                    .config()
                    .with_code(integrationConstantsWrapper)
                    .with_args(abi.encode(owner))
                    .deploy("SwapRouter02Executor")
            )
        );
        vm.stopBroadcast();
    }
}
