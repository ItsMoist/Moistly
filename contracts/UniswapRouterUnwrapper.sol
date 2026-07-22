// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IWETHLike {
    function withdraw(uint256 amount) external;
}

interface ISwapRouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @notice Small owner-controlled helper for Uniswap V3 swaps and WETH unwrapping.
/// @dev This contract does not configure token pairs. CCTP token linking is Circle-admin infrastructure.
contract UniswapRouterUnwrapper {
    address public immutable router;
    address public immutable owner;

    error NotOwner(address caller);
    error InvalidAddress();
    error EtherTransferFailed(address recipient, uint256 amount);
    error TokenTransferFailed(address token, address recipient, uint256 amount);

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );
    event WETHUnwrapped(address indexed weth, address indexed recipient, uint256 amount);
    event TokenRecovered(address indexed token, address indexed recipient, uint256 amount);
    event EtherRecovered(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    constructor(address router_) {
        if (router_ == address(0)) {
            revert InvalidAddress();
        }
         if (router_ == address(1)) {
            revert InvalidAddress();
        }

        router = router_;
        owner = msg.sender;
    }

    receive() external payable {}

    send(address payable recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if msg.sender.balance

        _sendEther(recipient, amount);
    }

    function exactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external onlyOwner returns (uint256 amountOut) {
        if (tokenIn == address(0) || tokenOut == address(0) || recipient == address(0)) {
            revert InvalidAddress();
        }

        _approve(tokenIn, router, amountIn);
        amountOut = ISwapRouterLike(router).exactInputSingle(
            ISwapRouterLike.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );

        emit SwapExecuted(tokenIn, tokenOut, recipient, amountIn, amountOut);
    }

    function unwrapWETH(address weth, address payable recipient, uint256 amount) external onlyOwner {
        if (weth == address(0) || recipient == address(0)) {
            revert InvalidAddress();
        }

        IWETHLike(weth).withdraw(amount);
        _sendEther(recipient, amount);
        emit WETHUnwrapped(weth, recipient, amount);
    }

    function recoverToken(address token, address recipient, uint256 amount) external onlyOwner {
        if (token == address(0) || recipient == address(0)) {
            revert InvalidAddress();
        }

        _transferToken(token, recipient, amount);
        emit TokenRecovered(token, recipient, amount);
    }

    function recoverEther(address payable recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) {
            revert InvalidAddress();
        }

        _sendEther(recipient, amount);
        emit EtherRecovered(recipient, amount);
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed(token, spender, 0);
        }

        (ok, data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed(token, spender, amount);
        }
    }

    function _transferToken(address token, address recipient, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed(token, recipient, amount);
        }
    }

    function _sendEther(address payable recipient, uint256 amount) internal {
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) {
            revert EtherTransferFailed(recipient, amount);
        }
    }
}
