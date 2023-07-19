// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
// import {SwapRouter02Executor} from "uniswapx/src/sample-executors/SwapRouter02Executor.sol";
import {SwapRouter02Executor} from "../../src/SwapRouter02ExecutorYul.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "uniswapx/src/reactors/DutchOrderReactor.sol";
import {MockERC20} from "uniswapx/test/util/mock/MockERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockSwapRouter} from "uniswapx/test/util/mock/MockSwapRouter.sol";
import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "uniswapx/src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "uniswapx/test/util/DeployPermit2.sol";
import {OrderInfoBuilder} from "uniswapx/test/util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "uniswapx/test/util/OutputsBuilder.sol";
import {PermitSignature} from "uniswapx/test/util/PermitSignature.sol";
import {ISwapRouter02, ExactInputParams} from "uniswapx/src/external/ISwapRouter02.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {HuffDeployer} from "foundry-huff/HuffDeployer.sol";

// This set of tests will use a mock swap router to simulate the Uniswap swap router.
contract SwapRouter02ExecutorTest is
    Test,
    PermitSignature,
    GasSnapshot,
    DeployPermit2
{
    using OrderInfoBuilder for OrderInfo;

    uint256 fillerPrivateKey;
    uint256 swapperPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    WETH weth;
    address filler;
    address swapper;
    SwapRouter02Executor swapRouter02Executor;
    MockSwapRouter mockSwapRouter;
    DutchOrderReactor reactor;
    IPermit2 permit2;

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    address constant PROTOCOL_FEE_OWNER = address(80085);

    // to test sweeping ETH
    receive() external payable {}

    function setUp() public {
        vm.warp(1000);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        weth = new WETH();

        // Mock filler and swapper
        fillerPrivateKey = 0x12341234;
        filler = vm.addr(fillerPrivateKey);
        swapperPrivateKey = 0x12341235;
        swapper = vm.addr(swapperPrivateKey);

        // Instantiate relevant contracts
        mockSwapRouter = new MockSwapRouter(address(weth));
        permit2 = IPermit2(deployPermit2());
        reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        // comment out to use the solidity version
        // swapRouter02Executor = new SwapRouter02Executor(
        //     address(this),
        //     reactor,
        //     address(this),
        //     ISwapRouter02(address(mockSwapRouter))
        // );

        swapRouter02Executor = SwapRouter02Executor(
            payable(
                HuffDeployer
                    .config()
                    .with_args(abi.encode(address(this)))
                    .deploy("SwapRouter02Executor")
            )
        );

        // vm.etch(
        //     address(swapRouter02Executor),
        //     hex"5f3560e01c80639943fa891461009157806363fb0b96146102f25780638d4558e614610460578063690d83201461055d57806313af40351461004b5780638da5cb5b146100845761008d565b335f5414610057575f5ffd5b600435805f55337f8292fce18fa69edf4db7b94ea2e58241df0ae57f97e0a6c9b29067028bf92d765f5fa3005b5f545f5260205ff35b5f5ffd5b3373c7183455a4c133ae270771860664b6b7ec320bb1146100d5577f933fe52f000000000000000000000000000000000000000000000000000000005f526004601cfd5b602435737fa9385be102ac3eac297483dd6233d62b3e14961461011b577f8c6e5d71000000000000000000000000000000000000000000000000000000005f526004601cfd5b604435806040013590602001355f90806020355b7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7368b3465833fb72a70ecdf485e0e4c7bd8665fc457f095ea7b30000000000000000000000000000000000000000000000000000000060005260006004015260006024015260006044815f6020945af13d1560005160011417166101bb57633e3f8f735f526004601cfd5b6001018181146101d1578060200282013561012f565b5050602081033603807fd6a0e487000000000000000000000000000000000000000000000000000000005f527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600452602060245281906044355f5f915f5f7368b3465833fb72a70ecdf485e0e4c7bd8665fc455af1610253573d5f5f3e3d5ffd5b5b6064355f6084355b60c001355f5b6060810282018060600135816040013582602001357fa9059cbb0000000000000000000000000000000000000000000000000000000060005260006004015260006024015260006044815f6020945af13d1560005160011417166102cd576390b8ec185f526004601cfd5b506001018181146102625750506001018181146102f0578060200260840161025c565b005b5f54331461032c5760205f52600c6020527f554e415554484f52495a4544000000000000000000000000000000000000000060405260605ffd5b6004356024355f90806020355b7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7368b3465833fb72a70ecdf485e0e4c7bd8665fc457f095ea7b30000000000000000000000000000000000000000000000000000000060005260006004015260006024015260006044815f6020945af13d1560005160011417166103c557633e3f8f735f526004601cfd5b6001018181146103db5780602002820135610339565b5050602081033603807fd6a0e487000000000000000000000000000000000000000000000000000000005f527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600452602060245281906044355f5f915f5f7368b3465833fb72a70ecdf485e0e4c7bd8665fc455af161045d573d5f5f3e3d5ffd5b5b005b5f54331461049a5760205f52600c6020527f554e415554484f52495a4544000000000000000000000000000000000000000060405260605ffd5b7f70a08231000000000000000000000000000000000000000000000000000000003d523060045260205f60243d73c02aaa39b223fe8d0a0e5c4f27ead9083c756cc25afa156104ea575f516104ee565b3434fd5b7f2e1a7d4d000000000000000000000000000000000000000000000000000000005f526004525f5f60245f73c02aaa39b223fe8d0a0e5c4f27ead9083c756cc25afa1561055557476004355f8080809490935af16105535763b12d13eb5f526004601cfd5b005b3d5f5f3e3d5ffd5b5f5433146105975760205f52600c6020527f554e415554484f52495a4544000000000000000000000000000000000000000060405260605ffd5b476004353d3d3d3d9490935af16105b55763b12d13eb5f526004601cfd5b00"
        // );
        // vm.store(
        //     address(swapRouter02Executor),
        //     bytes32(0),
        //     bytes32(uint256(uint160(address(this))))
        // );

        console2.log("len", address(swapRouter02Executor).code.length);
        console2.log("weth", address(weth));
        console2.log("executor", address(swapRouter02Executor));
        console2.log("reactor", address(reactor));
        console2.log("mockswap router", address(mockSwapRouter));
        console2.log("this", address(this));

        // Do appropriate max approvals
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[0].recipient = swapper;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );
        bytes memory fillData = abi.encode(
            tokensToApproveForSwapRouter02,
            multicallData
        );

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.prank(address(reactor));
        swapRouter02Executor.reactorCallback(
            resolvedOrders,
            address(this),
            fillData
        );
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(address(swapper)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in SwapRouter02Executor.
    function testExecute2() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(tokenOut),
                ONE,
                0,
                address(swapper)
            )
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );

        reactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(permit2), order)
            ),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(swapper), ONE / 2);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), ONE / 2);
    }

    error TransferFailed();
    error InsufficientOutput(uint256, uint256);

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
    function testExecuteInsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(
                address(tokenOut),
                ONE * 2,
                ONE * 2,
                address(swapper)
            )
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientOutput.selector, 0, 2e18)
        );
        reactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(permit2), order)
            ),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
    // and outputs = [2]. Mint swapper 10 input and mint mockSwapRouter 10 output. After
    // the execution, swapper should have 6 input / 3 output, mockSwapRouter should have
    // 4 input / 6 output, and swapRouter02Executor should have 0 input / 1 output.
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 10);
        tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(
                address(tokenOut),
                outputAmount,
                outputAmount,
                swapper
            )
        });
        bytes memory sig1 = signOrder(
            swapperPrivateKey,
            address(permit2),
            order1
        );
        signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount * 3, inputAmount * 3),
            outputs: OutputsBuilder.singleDutch(
                address(tokenOut),
                outputAmount * 2,
                outputAmount * 2,
                swapper
            )
        });
        bytes memory sig2 = signOrder(
            swapperPrivateKey,
            address(permit2),
            order2
        );
        signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: inputAmount * 4,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );

        reactor.executeBatch(
            signedOrders,
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
        assertEq(tokenOut.balanceOf(swapper), 3 ether);
        assertEq(tokenIn.balanceOf(swapper), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 10 ** 18);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
    }

    function testNotWhitelistedCaller() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(tokenOut),
                ONE,
                0,
                address(swapper)
            )
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );

        vm.prank(address(0xbeef));
        vm.expectRevert(SwapRouter02Executor.CallerNotWhitelisted.selector);
        reactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(permit2), order)
            ),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Very similar to `testReactorCallback`, but do not vm.prank the reactor when calling `reactorCallback`, so reverts
    // in
    function testMsgSenderNotReactor() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.exactInput.selector,
            exactInputParams
        );
        bytes memory fillData = abi.encode(
            tokensToApproveForSwapRouter02,
            multicallData
        );

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder
                .init(address(reactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.expectRevert(SwapRouter02Executor.MsgSenderNotReactor.selector);
        swapRouter02Executor.reactorCallback(
            resolvedOrders,
            address(this),
            fillData
        );
    }

    function testUnwrapWETH() public {
        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(swapRouter02Executor), ONE);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.unwrapWETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    error UNAUTHORIZED();

    function testUnwrapWETHNotOwner() public {
        vm.expectRevert(UNAUTHORIZED.selector);
        vm.prank(address(0xbeef));
        swapRouter02Executor.unwrapWETH(address(this));
    }

    function testWithdrawETH() public {
        vm.deal(address(swapRouter02Executor), 1 ether);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.withdrawETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testWithdrawETHNotOwner() public {
        vm.expectRevert(UNAUTHORIZED.selector);
        vm.prank(address(0xbeef));
        swapRouter02Executor.withdrawETH(address(this));
    }
}
