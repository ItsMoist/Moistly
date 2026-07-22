
/** 
 *  SourceUnit: /Users/bnelligan/DAPP/Moistly/contracts/MevModuleReplacement.sol
*/

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.28;

interface IERC20Minimal {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IAccessHubMinimal {
    function treasury() external view returns (address);
}

interface ISwapRouterMinimal {}
interface IPairFactoryMinimal {}
interface IRouterMinimal {}

/// @notice Storage-compatible replacement for the Ramses MevModule proxy.
/// @dev This preserves the original storage layout and external ABI while
///      disabling fee-switching MEV execution. It is intended as a defensive
///      upgrade target, not a feature-complete arbitrage module.
contract MevModuleReplacement {
    struct AddressSet {
        address[] values;
        mapping(address => uint256) positions;
    }

    struct AuthorizedSwapParams {
        address[] poolAddresses;
        uint24[] originalFees;
        uint24[] targetFees;
        bool[] concentrated;
    }

    struct SwapIntent {
        address tokenIn;
        address tokenOut;
        int24 feeOrTickspace;
        PoolType poolType;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    enum PoolType {
        LEGACY_STABLE,
        LEGACY_VOLATILE,
        V3
    }

    enum PayloadType {
        ROUTER,
        EXECUTOR
    }

    address public constant RAM = 0x555570a286F15EbDFE42B66eDE2f724Aa1AB5555;
    address public constant XRAM = 0xAE6D5FcE541216BDA471D311425B5412D9f1DEb9;
    address public constant X33 = 0x5555c2542836e7a6c8D3E133D5AA9773b65D5555;
    address public constant WETH = 0x5555555555555555555555555555555555555555;
    address public constant RAMSES_MULTISIG = 0x20D630cF1f5628285BfB91DfaC8C89eB9087BE1A;
    uint256 public constant INVENTORY_FLOOR = 500 * 1e18;

    // Original MevModule storage layout. Do not reorder or insert fields.
    AddressSet private _authorizedExecutors;
    IAccessHubMinimal public accessHub;
    ISwapRouterMinimal public swapRouter;
    IPairFactoryMinimal public pairFactory;
    IRouterMinimal public legacyRouter;
    uint256 public totalBuybackAndBurned;

    error InvalidInitialization();
    error NotImplemented();
    error NotInitializing();
    error Unauthorized();
    error Unprofitable(uint256 initialBalance, uint256 finalBalance);
    error TransferFailed(address token, address recipient, uint256 amount);

    event BuybackAndBurn(uint256 amountIn, uint256 amountOut);
    event Initialized(uint64 version);
    event ExecutorUpdated(address indexed executor, bool active);
    event RouterUpdated(address indexed swapRouter, address indexed legacyRouter);
    event TokenClawedBack(address indexed token, address indexed recipient, uint256 amount);
    event NativeClawedBack(address indexed recipient, uint256 amount);

    receive() external payable {}

    function initialize() external pure {
        revert InvalidInitialization();
    }

    function addAuthorizedExecutor(address _executor, bool _isActive) external onlyMultisig {
        if (_isActive) {
            _add(_executor);
        } else {
            _remove(_executor);
        }
        emit ExecutorUpdated(_executor, _isActive);
    }

    function isAuthorizedExecutor(address _executor) external view returns (bool) {
        return _contains(_executor);
    }

    function authorizedExecutorsCount() external view returns (uint256) {
        return _authorizedExecutors.values.length;
    }

    function amo(
        ExactInputSingleParams calldata,
        AuthorizedSwapParams calldata,
        bool,
        bool
    ) external view onlyAuthorizedExecutor {
        revert NotImplemented();
    }

    function backrun(
        PayloadType,
        SwapIntent[] calldata,
        uint256,
        AuthorizedSwapParams calldata,
        bool
    ) external view onlyAuthorizedExecutor returns (uint256) {
        revert NotImplemented();
    }

    function singleQuoteAuthorizedSwap(
        SwapIntent calldata,
        uint256,
        AuthorizedSwapParams calldata,
        bool
    ) external view onlyAuthorizedExecutor returns (uint256) {
        revert NotImplemented();
    }

    function buyBackAndBurn() external view onlyAuthorizedExecutor {
        revert NotImplemented();
    }

    function initApprovals() external onlyMultisig {
        _forceApprove(RAM, XRAM, type(uint256).max);
        _forceApprove(XRAM, X33, type(uint256).max);
    }

    function sanitizeApprovals(address[] calldata _tokens) external onlyMultisig {
        address currentSwapRouter = address(swapRouter);
        address currentLegacyRouter = address(legacyRouter);

        for (uint256 i; i < _tokens.length; i++) {
            if (currentSwapRouter != address(0)) {
                _forceApprove(_tokens[i], currentSwapRouter, 0);
            }
            if (currentLegacyRouter != address(0)) {
                _forceApprove(_tokens[i], currentLegacyRouter, 0);
            }
            _forceApprove(_tokens[i], XRAM, 0);
            _forceApprove(_tokens[i], X33, 0);
        }
    }

    function setSwapRouter(address _swapRouter) external onlyMultisig {
        swapRouter = ISwapRouterMinimal(_swapRouter);
        emit RouterUpdated(_swapRouter, address(legacyRouter));
    }

    function setLegacyRouter(address _legacyRouter) external onlyMultisig {
        legacyRouter = IRouterMinimal(_legacyRouter);
        emit RouterUpdated(address(swapRouter), _legacyRouter);
    }

    function clawBackToMultisig(address _token, uint256 _amount) external onlyMultisig {
        address recipient = _treasury();
        if (_token == address(0)) {
            (bool ok,) = payable(recipient).call{value: _amount}("");
            if (!ok) {
                revert TransferFailed(_token, recipient, _amount);
            }
            emit NativeClawedBack(recipient, _amount);
            return;
        }

        bool transferred = IERC20Minimal(_token).transfer(recipient, _amount);
        if (!transferred) {
            revert TransferFailed(_token, recipient, _amount);
        }
        emit TokenClawedBack(_token, recipient, _amount);
    }

    modifier onlyAuthorizedExecutor() {
        if (!_contains(msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyMultisig() {
        if (msg.sender != _treasury()) {
            revert Unauthorized();
        }
        _;
    }

    function _treasury() internal view returns (address treasury) {
        address hub = address(accessHub);
        if (hub != address(0)) {
            try accessHub.treasury() returns (address resolved) {
                if (resolved != address(0)) {
                    return resolved;
                }
            } catch {}
        }
        return RAMSES_MULTISIG;
    }

    function _contains(address value) internal view returns (bool) {
        return _authorizedExecutors.positions[value] != 0;
    }

    function _add(address value) internal returns (bool) {
        if (_contains(value)) {
            return false;
        }
        _authorizedExecutors.values.push(value);
        _authorizedExecutors.positions[value] = _authorizedExecutors.values.length;
        return true;
    }

    function _remove(address value) internal returns (bool) {
        uint256 position = _authorizedExecutors.positions[value];
        if (position == 0) {
            return false;
        }

        uint256 valueIndex = position - 1;
        uint256 lastIndex = _authorizedExecutors.values.length - 1;

        if (valueIndex != lastIndex) {
            address lastValue = _authorizedExecutors.values[lastIndex];
            _authorizedExecutors.values[valueIndex] = lastValue;
            _authorizedExecutors.positions[lastValue] = position;
        }

        _authorizedExecutors.values.pop();
        delete _authorizedExecutors.positions[value];
        return true;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (token == address(0) || spender == address(0)) {
            return;
        }

        (bool ok, bytes memory result) = token.call(abi.encodeCall(IERC20Minimal.approve, (spender, amount)));
        if (!ok || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TransferFailed(token, spender, amount);
        }
    }
}

