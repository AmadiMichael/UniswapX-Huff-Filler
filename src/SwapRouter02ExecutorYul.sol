// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "uniswapx/src/interfaces/IReactorCallback.sol";
import {IReactor} from "uniswapx/src/interfaces/IReactor.sol";
import {CurrencyLibrary} from "uniswapx/src/lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "uniswapx/src/base/ReactorStructs.sol";
import {ISwapRouter02} from "uniswapx/src/external/ISwapRouter02.sol";
import {console2} from "forge-std/console2.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an adress other than the reactor
    error MsgSenderNotReactor();

    ISwapRouter02 private immutable swapRouter02;
    address private immutable whitelistedCaller;
    IReactor private immutable reactor;
    WETH private immutable weth;

    constructor(
        address _whitelistedCaller,
        IReactor _reactor,
        address _owner,
        ISwapRouter02 _swapRouter02
    ) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        swapRouter02 = _swapRouter02;
        weth = WETH(payable(_swapRouter02.WETH9()));
    }

    /// @param resolvedOrders The orders to fill
    /// @param filler This filler must be `whitelistedCaller`
    /// @param fillData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        address filler,
        bytes calldata fillData
    ) external {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        if (filler != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }

        (
            address[] memory tokensToApproveForSwapRouter02,
            bytes[] memory multicallData
        ) = abi.decode(fillData, (address[], bytes[]));

        for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
            ERC20(tokensToApproveForSwapRouter02[i]).safeApprove(
                address(swapRouter02),
                type(uint256).max
            );
        }

        swapRouter02.multicall(type(uint256).max, multicallData);

        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];
                output.token.transfer(output.recipient, output.amount);
            }
        }

        console2.log("omo");
        assembly {
            for {
                let i := 0
            } lt(i, resolvedOrders.length) {
                i := add(i, 0x01)
            } {
                let indexOffset := mul(0x20, i)
                let contextOffset := add(0x84, indexOffset)

                let outputsLengthOffset := add(
                    calldataload(
                        add(add(calldataload(contextOffset), 0x64), 0x80)
                    ),
                    contextOffset
                )
                let outputsLength := calldataload(outputsLengthOffset)
                for {
                    let j := 0
                } lt(j, outputsLength) {
                    j := add(j, 0x01)
                } {
                    let token := calldataload(add(0x20, outputsLengthOffset))
                    let amount := calldataload(add(0x40, outputsLengthOffset))
                    let recipient := calldataload(
                        add(0x60, outputsLengthOffset)
                    )

                    mstore(0x00, hex"a9059cbb")
                    mstore(0x04, recipient)
                    mstore(0x24, amount)

                    let success := and(
                        // Set success to whether the call reverted, if not we check it either
                        // returned exactly 1 (can't just be non-zero data), or had no return data.
                        or(
                            and(eq(mload(0), 1), gt(returndatasize(), 31)),
                            iszero(returndatasize())
                        ),
                        call(gas(), token, 0x00, 0x00, 0x44, 0x00, 0x00)
                    )

                    if iszero(success) {
                        mstore(0x00, 0x20)
                        mstore(0x20, 0x0f)
                        mstore(
                            0x40,
                            0x5452414e534645525f4641494c45440000000000000000000000000000000000
                        )

                        revert(0x00, 0x4f)
                    }
                }
            }
        }
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(
        ERC20[] calldata tokensToApprove,
        bytes[] calldata multicallData
    ) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            tokensToApprove[i].safeApprove(
                address(swapRouter02),
                type(uint256).max
            );
        }
        swapRouter02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}
}
