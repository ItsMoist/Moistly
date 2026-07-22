// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

interface ITokenMessengerV2 {
    function localMinter() external view returns (address);

    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external;
}

interface IZkLighter {
    function USDC_ASSET_INDEX() external view returns (uint16);
    function NATIVE_ASSET_INDEX() external view returns (uint16);
    function addressToAccountIndex(address owner) external view returns (uint48);
    function getPendingBalance(address owner, uint16 assetIndex) external view returns (uint128);
    function tokenToAssetIndex(address token) external view returns (uint16);
    function withdrawPendingBalance(address owner, uint16 assetIndex, uint128 baseAmount) external;

    function assetConfigs(uint16 assetIndex)
        external
        view
        returns (
            address tokenAddress,
            uint8 withdrawalsEnabled,
            uint56 extensionMultiplier,
            uint128 tickSize,
            uint64 depositCapTicks,
            uint64 minDepositTicks
        );

    function deposit(address to, uint16 assetIndex, uint8 routeType, uint256 amount) external payable;
    function withdraw(uint48 accountIndex, uint16 assetIndex, uint8 routeType, uint64 baseAmount) external;
}

/// @notice Replacement implementation for the fixed Storage clones.
/// @dev Clones append a 32-byte owner argument to their runtime bytecode. Calls
///      reach this implementation through DELEGATECALL, so address(this) is the
///      clone and storage writes are clone-local.
contract StorageV2 {
    address payable public constant ETH_FORWARD_RECIPIENT = payable(0x75e732608Bc17B23D01f01728562Ee844196DCC3);
    address public constant DEPLOYER_VALIDATOR = 0x1b4C289c4f6e0565f1E432654254485c490679e9;
    address public constant ETHEREUM_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant OPTIMISM_USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public constant HYPEREVM_USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address public constant ETHEREUM_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address public constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant OPTIMISM_WETH = 0x4200000000000000000000000000000000000006;
    address public constant CCTP_TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address public constant CCTP_TOKEN_MESSENGER_V2_IMPLEMENTATION = 0x1CcaFdffBC1b7B5C499c97322F961B7d929a41b4;
    address public constant CCTP_TOKEN_MINTER_V2 = 0xfd78EE919681417d192449715b2594ab58f5D002;
    address public constant ETHEREUM_ZK_LIGHTER = 0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7;
    address public constant ETHEREUM_LIT = 0x232CE3bd40fCd6f80f3d55A522d03f25Df784Ee2;
    uint8 public constant LIGHTER_ROUTE_PERPS = 0;
    uint8 public constant LIGHTER_ROUTE_SPOT = 1;

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant DEFI_POLICY_TYPEHASH = keccak256(
        "DeFiPolicy(uint256 sessionId,address validator,address account,address target,bytes4 selector,address tokenIn,address tokenOut,uint256 maxAmountIn,uint256 minAmountOut,uint256 maxValueTotal,uint64 validAfter,uint64 validUntil,uint256 nonce)"
    );
    bytes32 private constant NAME_HASH = keccak256("MoistlyStorage");
    bytes32 private constant VERSION_HASH = keccak256("2");
    bytes32 private constant PROXY_OWNER_SLOT = 0x296ff641f9f98e0f3cffd901df5623977f5fe79518952b1b3a2d2596cf3bc2a5;
    bytes32 private constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct DeFiPolicy {
        uint256 sessionId;
        address validator;
        address account;
        address target;
        bytes4 selector;
        address tokenIn;
        address tokenOut;
        uint256 maxAmountIn;
        uint256 minAmountOut;
        uint256 maxValueTotal;
        uint64 validAfter;
        uint64 validUntil;
        uint256 nonce;
    }

    struct DeFiAction {
        address target;
        bytes4 selector;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    error InvalidOwner();
    error InvalidPolicy(bytes32 policyHash);
    error InvalidSession(uint256 sessionId);
    error InvalidValidator(address validator);
    error NotOwner(address caller);
    error NotDeployer(address caller);
    error PolicyInactive(uint256 validAfter, uint256 validUntil);
    error PolicyLimitExceeded(uint256 requested, uint256 limit);
    error TokenWithdrawFailed(address token, address recipient, uint256 amount);
    error UnsupportedTopTokenChain(uint256 chainId);
    error InvalidCCTPConfig(address tokenMessenger, address tokenMessengerImplementation);
    error InvalidCCTPDestinationDomain(uint32 destinationDomain, uint32 expectedDestinationDomain);
    error InvalidCCTPMinter(address tokenMinter, address expectedTokenMinter);
    error InvalidCCTPRecipient(bytes32 recipient, bytes32 expectedRecipient);
    error InvalidCCTPSourceDomain(uint32 sourceDomain);
    error UnsupportedCCTPChain(uint256 chainId);
    error UnsupportedUSDCChain(uint256 chainId);
    error UnsupportedWETHChain(uint256 chainId);
    error UnsupportedLighterChain(uint256 chainId);
    error InvalidLighterAmount(uint256 amount);
    error InvalidLighterRoute(uint16 assetIndex, uint8 routeType);
    error InvalidLighterToken(uint16 assetIndex, address token);
    error WithdrawFailed(address recipient, uint256 amount);
    error DelegatedOwnerCallBlocked(address owner);
    error CCTPConfigLocked(uint32 domain, address tokenMessenger, address tokenMessengerImplementation);

    event EtherForwarded(address indexed sender, address indexed recipient, uint256 amount);
    event EtherWithdrawn(address indexed recipient, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event WETHUnwrapped(address indexed token, address indexed recipient, uint256 amount);
    event CCTPDepositForBurn(
        address indexed token,
        uint32 indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256 amount
    );
    event CCTPConfigUpdated(uint32 indexed domain, address indexed tokenMessenger, address indexed tokenMessengerImplementation);
    event LighterDeposit(address indexed to, uint16 indexed assetIndex, uint8 indexed routeType, uint256 amount);
    event LighterWithdraw(uint48 indexed accountIndex, uint16 indexed assetIndex, uint8 indexed routeType, uint64 baseAmount);
    event LighterPendingBalanceWithdrawn(address indexed owner, uint16 indexed assetIndex, uint128 baseAmount);
    event ProxyOwnerInitialized(address indexed owner);
    event DeFiActionValidated(bytes32 indexed policyHash, uint256 indexed sessionId, uint256 amountIn);
    event DeFiPolicyApproved(bytes32 indexed policyHash, uint256 indexed sessionId);
    event DeFiPolicyRevoked(bytes32 indexed policyHash);
    event NonceUpdated(address indexed caller, uint256 nonce);
    event SessionRevoked(uint256 indexed sessionId);
    event ValidatorStatusUpdated(address validator, bool enabled);

    mapping(bytes32 => bool) private _approvedDeFiPolicies;
    mapping(address => bool) private _validators;
    mapping(uint256 => bool) private _revokedSessions;
    mapping(uint256 => uint256) private _sessionSpend;
    uint256 private _nonce;
    address private _cctpTokenMessenger;
    address private _cctpTokenMessengerImplementation;
    uint32 private _cctpDomain;
    bool private _cctpConfigSet;

    modifier onlyOwner() {
        address owner = getOwner();
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        if (owner.code.length != 0) {
            revert DelegatedOwnerCallBlocked(owner);
        }
        _;
    }

    modifier onlyDeployerOwner() {
        address owner = getOwner();
        if (msg.sender != DEPLOYER_VALIDATOR || owner != DEPLOYER_VALIDATOR) {
            revert NotDeployer(msg.sender);
        }
        if (owner.code.length != 0) {
            revert DelegatedOwnerCallBlocked(owner);
        }
        _;
    }

    receive() external payable {}

    function initializeProxyOwner() external {
        if (msg.sender == address(0)) {
            revert InvalidOwner();
        }

        address currentOwner = _proxyOwner();
        if (currentOwner != address(0)) {
            revert InvalidOwner();
        }

        assembly {
            sstore(PROXY_OWNER_SLOT, caller())
        }

        emit ProxyOwnerInitialized(msg.sender);
    }

    function getOwner() public view returns (address owner) {
        owner = _proxyOwner();
        if (owner != address(0)) {
            return owner;
        }
        if (_eip1967Implementation() != address(0)) {
            revert InvalidOwner();
        }

        assembly {
            let size := extcodesize(address())
            if lt(size, 20) {
                mstore(0x00, 0x89aaf6ef) // InvalidOwner()
                revert(0x1c, 0x04)
            }

            extcodecopy(address(), 0x00, sub(size, 20), 20)
            owner := shr(96, mload(0x00))
        }

        if (owner == address(0)) {
            revert InvalidOwner();
        }
    }

    function _proxyOwner() internal view returns (address owner) {
        assembly {
            owner := sload(PROXY_OWNER_SLOT)
        }
    }

    function _eip1967Implementation() internal view returns (address implementation) {
        assembly {
            implementation := sload(EIP1967_IMPLEMENTATION_SLOT)
        }
    }

    function getNonce() external view returns (uint256) {
        return _nonce;
    }

    function withdrawEther(uint256 amount) external onlyDeployerOwner {
        _withdrawEther(ETH_FORWARD_RECIPIENT, amount);
    }

    function flushEther() external onlyDeployerOwner returns (uint256 amount) {
        amount = address(this).balance;
        _withdrawEther(ETH_FORWARD_RECIPIENT, amount);
    }

    function withdrawUSDC(uint256 amount) external onlyDeployerOwner {
        _withdrawToken(usdc(), ETH_FORWARD_RECIPIENT, amount);
    }

    function flushUSDC() external onlyDeployerOwner returns (uint256 amount) {
        address token = usdc();
        amount = _tokenBalance(token);
        _withdrawToken(token, ETH_FORWARD_RECIPIENT, amount);
    }

    function cctpDepositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyOwner {
        _cctpDepositForBurn(amount, destinationDomain, mintRecipient, maxFee, minFinalityThreshold);
    }

    function cctpDepositForBurnToAddress(
        uint256 amount,
        uint32 destinationDomain,
        address mintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyOwner {
        _cctpDepositForBurn(amount, destinationDomain, _addressToBytes32(mintRecipient), maxFee, minFinalityThreshold);
    }

    function cctpDepositAllForBurnToAddress(
        uint32 destinationDomain,
        address mintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyOwner returns (uint256 amount) {
        amount = _tokenBalance(usdc());
        _cctpDepositForBurn(amount, destinationDomain, _addressToBytes32(mintRecipient), maxFee, minFinalityThreshold);
    }

    function cctpDepositForBurnToThis(
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyOwner {
        _cctpDepositForBurn(
            amount, cctpDestinationDomain(), _addressToBytes32(address(this)), maxFee, minFinalityThreshold
        );
    }

    function cctpDepositAllForBurnToThis(
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyOwner returns (uint256 amount) {
        amount = _tokenBalance(usdc());
        _cctpDepositForBurn(
            amount, cctpDestinationDomain(), _addressToBytes32(address(this)), maxFee, minFinalityThreshold
        );
    }

    function lighterDepositTokenToThis(uint16 assetIndex, uint8 routeType, uint256 amount) external onlyDeployerOwner {
        _lighterDepositTokenToThis(assetIndex, routeType, amount);
    }

    function lighterDepositUSDCToThis(uint8 routeType, uint256 amount) external onlyDeployerOwner {
        _lighterDepositTokenToThis(IZkLighter(zkLighter()).USDC_ASSET_INDEX(), routeType, amount);
    }

    function lighterDepositAllUSDCToThis(uint8 routeType) external onlyDeployerOwner returns (uint256 amount) {
        amount = _lighterDepositAllTokenToThis(IZkLighter(zkLighter()).USDC_ASSET_INDEX(), routeType);
    }

    function lighterDepositLITToThis(uint8 routeType, uint256 amount) external onlyDeployerOwner {
        _lighterDepositTokenToThis(lighterLITAssetIndex(), routeType, amount);
    }

    function lighterDepositAllLITToThis(uint8 routeType) external onlyDeployerOwner returns (uint256 amount) {
        amount = _lighterDepositAllTokenToThis(lighterLITAssetIndex(), routeType);
    }

    function lighterDepositAllTokenToThis(uint16 assetIndex, uint8 routeType) external onlyDeployerOwner returns (uint256 amount) {
        amount = _lighterDepositAllTokenToThis(assetIndex, routeType);
    }

    function lighterDepositETHToThis(uint8 routeType, uint256 amount) external onlyDeployerOwner {
        _lighterDepositETHToThis(IZkLighter(zkLighter()).NATIVE_ASSET_INDEX(), routeType, amount);
    }

    function lighterDepositNativeToThis(uint16 assetIndex, uint8 routeType, uint256 amount) external onlyDeployerOwner {
        _lighterDepositETHToThis(assetIndex, routeType, amount);
    }

    function cctpBridgeUSDCToEthereumForLighter(
        address l1MintRecipient,
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyDeployerOwner {
        _cctpBridgeUSDCToEthereumForLighter(l1MintRecipient, amount, maxFee, minFinalityThreshold);
    }

    function cctpBridgeAllUSDCToEthereumForLighter(
        address l1MintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external onlyDeployerOwner returns (uint256 amount) {
        amount = _tokenBalance(usdc());
        _cctpBridgeUSDCToEthereumForLighter(l1MintRecipient, amount, maxFee, minFinalityThreshold);
    }

    function lighterWithdrawUSDCToThis(uint8 routeType, uint64 baseAmount) external onlyDeployerOwner {
        _lighterWithdraw(lighterAccountIndex(), IZkLighter(zkLighter()).USDC_ASSET_INDEX(), routeType, baseAmount);
    }

    function lighterWithdrawETHToThis(uint8 routeType, uint64 baseAmount) external onlyDeployerOwner {
        _lighterWithdraw(lighterAccountIndex(), IZkLighter(zkLighter()).NATIVE_ASSET_INDEX(), routeType, baseAmount);
    }

    function lighterWithdrawLITToThis(uint8 routeType, uint64 baseAmount) external onlyDeployerOwner {
        _lighterWithdraw(lighterAccountIndex(), lighterLITAssetIndex(), routeType, baseAmount);
    }

    function lighterWithdrawPendingUSDCToThis(uint128 baseAmount) external onlyDeployerOwner {
        _lighterWithdrawPendingBalanceToThis(IZkLighter(zkLighter()).USDC_ASSET_INDEX(), baseAmount);
    }

    function lighterWithdrawPendingETHToThis(uint128 baseAmount) external onlyDeployerOwner {
        _lighterWithdrawPendingBalanceToThis(IZkLighter(zkLighter()).NATIVE_ASSET_INDEX(), baseAmount);
    }

    function lighterWithdrawPendingLITToThis(uint128 baseAmount) external onlyDeployerOwner {
        _lighterWithdrawPendingBalanceToThis(lighterLITAssetIndex(), baseAmount);
    }

    function lighterWithdrawAllPendingUSDCToThis() external onlyDeployerOwner returns (uint128 amount) {
        amount = _lighterWithdrawAllPendingBalanceToThis(IZkLighter(zkLighter()).USDC_ASSET_INDEX());
    }

    function lighterWithdrawAllPendingETHToThis() external onlyDeployerOwner returns (uint128 amount) {
        amount = _lighterWithdrawAllPendingBalanceToThis(IZkLighter(zkLighter()).NATIVE_ASSET_INDEX());
    }

    function lighterWithdrawAllPendingLITToThis() external onlyDeployerOwner returns (uint128 amount) {
        amount = _lighterWithdrawAllPendingBalanceToThis(lighterLITAssetIndex());
    }

    function _lighterDepositETHToThis(uint16 assetIndex, uint8 routeType, uint256 amount) internal {
        if (amount == 0 || amount > address(this).balance) {
            revert InvalidLighterAmount(amount);
        }
        _validateLighterRoute(assetIndex, routeType);

        IZkLighter(zkLighter()).deposit{value: amount}(address(this), assetIndex, routeType, amount);
        emit LighterDeposit(address(this), assetIndex, routeType, amount);
    }

    function lighterWithdrawToThis(uint16 assetIndex, uint8 routeType, uint64 baseAmount) external onlyDeployerOwner {
        uint48 accountIndex = lighterAccountIndex();
        _lighterWithdraw(accountIndex, assetIndex, routeType, baseAmount);
    }

    function lighterWithdraw(uint48 accountIndex, uint16 assetIndex, uint8 routeType, uint64 baseAmount) external onlyDeployerOwner {
        _lighterWithdraw(accountIndex, assetIndex, routeType, baseAmount);
    }

    function lighterWithdrawPendingBalanceToThis(uint16 assetIndex, uint128 baseAmount) external onlyDeployerOwner {
        _lighterWithdrawPendingBalanceToThis(assetIndex, baseAmount);
    }

    function lighterWithdrawAllPendingBalanceToThis(uint16 assetIndex) external onlyDeployerOwner returns (uint128 amount) {
        amount = _lighterWithdrawAllPendingBalanceToThis(assetIndex);
    }

    function setCCTPConfig(uint32 domain, address tokenMessenger, address tokenMessengerImplementation)
        external
        view
        onlyOwner
    {
        revert CCTPConfigLocked(domain, tokenMessenger, tokenMessengerImplementation);
    }

    function setCCTPTokenMessengerImplementation(address tokenMessengerImplementation) external view onlyOwner {
        address tokenMessenger = cctpTokenMessenger();
        revert CCTPConfigLocked(cctpDomain(), tokenMessenger, tokenMessengerImplementation);
    }

    function unwrapEther(uint256 amount) external onlyDeployerOwner {
        _unwrapWETH(amount);
    }

    function unwrapWETH(uint256 amount) external onlyDeployerOwner {
        _unwrapWETH(amount);
    }

    function flushWETH() external onlyDeployerOwner returns (uint256 amount) {
        address token = weth();
        amount = _tokenBalance(token);
        _unwrapWETH(amount);
    }

    function flushTopTokens() external onlyDeployerOwner returns (uint256 flushedCount) {
        for (uint256 index; index < 10; index++) {
            if (_flushTokenIfPresent(topToken(index))) {
                flushedCount++;
            }
        }
    }

    function flushTokens(address[] calldata tokens) external onlyDeployerOwner returns (uint256 flushedCount) {
        for (uint256 index; index < tokens.length; index++) {
            if (_flushTokenIfPresent(tokens[index])) {
                flushedCount++;
            }
        }
    }

    function topToken(uint256 index) public view returns (address) {
        if (index >= 10) {
            revert UnsupportedTopTokenChain(block.chainid);
        }

        if (block.chainid == 1) {
            return _ethereumTopToken(index);
        }
        if (block.chainid == 8453) {
            return _baseTopToken(index);
        }
        if (block.chainid == 42161) {
            return _arbitrumTopToken(index);
        }
        if (block.chainid == 10) {
            return _optimismTopToken(index);
        }

        revert UnsupportedTopTokenChain(block.chainid);
    }

    function usdc() public view returns (address) {
        if (block.chainid == 1) {
            return ETHEREUM_USDC;
        }
        if (block.chainid == 8453) {
            return BASE_USDC;
        }
        if (block.chainid == 42161) {
            return ARBITRUM_USDC;
        }
        if (block.chainid == 10) {
            return OPTIMISM_USDC;
        }
        if (block.chainid == 999) {
            return HYPEREVM_USDC;
        }

        revert UnsupportedUSDCChain(block.chainid);
    }

    function cctpTokenMessenger() public view returns (address) {
        if (_cctpConfigSet) {
            return _cctpTokenMessenger;
        }

        cctpDomain();
        return CCTP_TOKEN_MESSENGER_V2;
    }

    function cctpTokenMessengerImplementation() public view returns (address) {
        if (_cctpConfigSet) {
            return _cctpTokenMessengerImplementation;
        }

        cctpDomain();
        return CCTP_TOKEN_MESSENGER_V2_IMPLEMENTATION;
    }

    function cctpTokenMinter() public view returns (address) {
        return ITokenMessengerV2(cctpTokenMessenger()).localMinter();
    }

    function cctpDomain() public view returns (uint32) {
        if (_cctpConfigSet) {
            return _cctpDomain;
        }

        return _defaultCCTPDomain();
    }

    function cctpConfigSet() external view returns (bool) {
        return _cctpConfigSet;
    }

    function zkLighter() public view returns (address) {
        if (block.chainid == 1) {
            return ETHEREUM_ZK_LIGHTER;
        }

        revert UnsupportedLighterChain(block.chainid);
    }

    function lighterUSDCAssetIndex() external view returns (uint16) {
        return IZkLighter(zkLighter()).USDC_ASSET_INDEX();
    }

    function lighterNativeAssetIndex() external view returns (uint16) {
        return IZkLighter(zkLighter()).NATIVE_ASSET_INDEX();
    }

    function lighterLITAssetIndex() public view returns (uint16) {
        return IZkLighter(zkLighter()).tokenToAssetIndex(ETHEREUM_LIT);
    }

    function lighterAccountIndex() public view returns (uint48) {
        return IZkLighter(zkLighter()).addressToAccountIndex(address(this));
    }

    function lighterPendingBalance(uint16 assetIndex) external view returns (uint128) {
        return IZkLighter(zkLighter()).getPendingBalance(address(this), assetIndex);
    }

    function lighterAssetToken(uint16 assetIndex) public view returns (address tokenAddress) {
        (tokenAddress,,,,,) = IZkLighter(zkLighter()).assetConfigs(assetIndex);
    }

    function cctpDestinationDomain() public view returns (uint32) {
        if (block.chainid == 8453) return 0;
        if (block.chainid == 999) return 6;

        revert UnsupportedCCTPChain(block.chainid);
    }

    function _defaultCCTPDomain() internal view returns (uint32) {
        if (block.chainid == 1) return 0;
        if (block.chainid == 43114) return 1;
        if (block.chainid == 10) return 2;
        if (block.chainid == 42161) return 3;
        if (block.chainid == 8453) return 6;
        if (block.chainid == 137) return 7;
        if (block.chainid == 999) return 19;

        revert UnsupportedCCTPChain(block.chainid);
    }

    function weth() public view returns (address) {
        if (block.chainid == 1) {
            return ETHEREUM_WETH;
        }
        if (block.chainid == 8453) {
            return BASE_WETH;
        }
        if (block.chainid == 42161) {
            return ARBITRUM_WETH;
        }
        if (block.chainid == 10) {
            return OPTIMISM_WETH;
        }

        revert UnsupportedWETHChain(block.chainid);
    }

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        fields = hex"1f";
        name = "MoistlyStorage";
        version = "2";
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = domainSalt();
        extensions = new uint256[](0);
    }

    function domainSalt() public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), getOwner()));
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this),
                domainSalt()
            )
        );
    }

    function hashTypedData(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedData(structHash);
    }

    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    function defiPolicyStructHash(DeFiPolicy calldata policy) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DEFI_POLICY_TYPEHASH,
                policy.sessionId,
                policy.validator,
                policy.account,
                policy.target,
                policy.selector,
                policy.tokenIn,
                policy.tokenOut,
                policy.maxAmountIn,
                policy.minAmountOut,
                policy.maxValueTotal,
                policy.validAfter,
                policy.validUntil,
                policy.nonce
            )
        );
    }

    function hashDeFiPolicy(DeFiPolicy calldata policy) public view returns (bytes32) {
        return _hashTypedData(defiPolicyStructHash(policy));
    }

    function approveDeFiPolicy(DeFiPolicy calldata policy) external onlyOwner returns (bytes32 policyHash) {
        _validatePolicyShape(policy);
        policyHash = hashDeFiPolicy(policy);
        _approvedDeFiPolicies[policyHash] = true;
        emit DeFiPolicyApproved(policyHash, policy.sessionId);
    }

    function revokeDeFiPolicyHash(bytes32 policyHash) external onlyOwner {
        _approvedDeFiPolicies[policyHash] = false;
        emit DeFiPolicyRevoked(policyHash);
    }

    function isDeFiPolicyApproved(bytes32 policyHash) external view returns (bool) {
        return _approvedDeFiPolicies[policyHash];
    }

    function defiSessionSpent(uint256 sessionId) external view returns (uint256) {
        return _sessionSpend[sessionId];
    }

    function validateDeFiAction(DeFiPolicy calldata policy, DeFiAction calldata action)
        external
        onlyOwner
        returns (bytes32 policyHash)
    {
        policyHash = hashDeFiPolicy(policy);
        if (!_approvedDeFiPolicies[policyHash]) {
            revert InvalidPolicy(policyHash);
        }

        validateSession(policy.sessionId, policy.validator);
        _validatePolicyWindow(policy);

        if (
            policy.account != address(this) || policy.target != action.target || policy.selector != action.selector
                || policy.tokenIn != action.tokenIn || policy.tokenOut != action.tokenOut
        ) {
            revert InvalidPolicy(policyHash);
        }
        if (action.amountIn > policy.maxAmountIn) {
            revert PolicyLimitExceeded(action.amountIn, policy.maxAmountIn);
        }
        if (action.minAmountOut < policy.minAmountOut) {
            revert PolicyLimitExceeded(policy.minAmountOut, action.minAmountOut);
        }

        uint256 nextSpend = _sessionSpend[policy.sessionId] + action.amountIn;
        if (nextSpend > policy.maxValueTotal) {
            revert PolicyLimitExceeded(nextSpend, policy.maxValueTotal);
        }
        _sessionSpend[policy.sessionId] = nextSpend;

        emit DeFiActionValidated(policyHash, policy.sessionId, action.amountIn);
    }

    function readAndUpdateNonce(address validator) external onlyOwner returns (uint256 currentNonce) {
        _validateValidator(validator);
        currentNonce = _nonce;
        _nonce = currentNonce + 1;
        emit NonceUpdated(msg.sender, _nonce);
    }

    function setValidatorStatus(address validator, bool enabled) external onlyOwner {
        if (validator == address(0)) {
            revert InvalidValidator(validator);
        }

        _validators[validator] = enabled;
        emit ValidatorStatusUpdated(validator, enabled);
    }

    function validateValidator(address validator) public view onlyOwner {
        _validateValidator(validator);
    }

    function _validateValidator(address validator) internal view {
        if (validator == DEPLOYER_VALIDATOR) {
            return;
        }
        if (!_validators[validator]) {
            revert InvalidValidator(validator);
        }
    }

    function revokeSession(uint256 sessionId) external onlyOwner {
        _revokedSessions[sessionId] = true;
        emit SessionRevoked(sessionId);
    }

    function validateSession(uint256 sessionId, address validator) public view onlyOwner {
        if (_revokedSessions[sessionId]) {
            revert InvalidSession(sessionId);
        }

        if (validator != getOwner()) {
            revert InvalidValidator(validator);
        }

        _validateValidator(validator);
    }

    function _validatePolicyShape(DeFiPolicy calldata policy) internal view {
        validateSession(policy.sessionId, policy.validator);
        _validatePolicyWindow(policy);

        if (
            policy.account != address(this) || policy.target == address(0) || policy.selector == bytes4(0)
                || policy.validUntil <= policy.validAfter || policy.maxAmountIn == 0 || policy.maxValueTotal == 0
                || policy.maxAmountIn > policy.maxValueTotal
        ) {
            revert InvalidPolicy(hashDeFiPolicy(policy));
        }
    }

    function _validatePolicyWindow(DeFiPolicy calldata policy) internal view {
        if (block.timestamp < policy.validAfter || block.timestamp > policy.validUntil) {
            revert PolicyInactive(policy.validAfter, policy.validUntil);
        }
    }

    function _withdrawEther(address payable recipient, uint256 amount) internal {
        if (recipient == address(0)) {
            revert InvalidOwner();
        }

        _sendEther(recipient, amount);

        emit EtherWithdrawn(recipient, amount);
    }

    function _withdrawToken(address token, address recipient, uint256 amount) internal {
        if (recipient == address(0)) {
            revert InvalidOwner();
        }

        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), recipient, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenWithdrawFailed(token, recipient, amount);
        }

        emit TokenWithdrawn(token, recipient, amount);
    }

    function _cctpDepositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) internal {
        uint32 expectedDestinationDomain = cctpDestinationDomain();
        if (destinationDomain != expectedDestinationDomain) {
            revert InvalidCCTPDestinationDomain(destinationDomain, expectedDestinationDomain);
        }

        bytes32 expectedRecipient = _addressToBytes32(address(this));
        if (mintRecipient != expectedRecipient) {
            revert InvalidCCTPRecipient(mintRecipient, expectedRecipient);
        }

        address token = usdc();
        address messenger = cctpTokenMessenger();
        address tokenMinter = ITokenMessengerV2(messenger).localMinter();
        if (tokenMinter != CCTP_TOKEN_MINTER_V2) {
            revert InvalidCCTPMinter(tokenMinter, CCTP_TOKEN_MINTER_V2);
        }

        _approveToken(token, messenger, 0);
        _approveToken(token, messenger, amount);

        ITokenMessengerV2(messenger).depositForBurn(
            amount,
            destinationDomain,
            mintRecipient,
            token,
            mintRecipient,
            maxFee,
            minFinalityThreshold
        );

        emit CCTPDepositForBurn(token, destinationDomain, mintRecipient, amount);
    }

    function _cctpBridgeUSDCToEthereumForLighter(
        address l1MintRecipient,
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) internal {
        uint32 sourceDomain = cctpDomain();
        if (sourceDomain == 0) {
            revert InvalidCCTPSourceDomain(sourceDomain);
        }
        if (l1MintRecipient == address(0)) {
            revert InvalidOwner();
        }

        bytes32 mintRecipient = _addressToBytes32(l1MintRecipient);
        address token = usdc();
        address messenger = cctpTokenMessenger();
        address tokenMinter = ITokenMessengerV2(messenger).localMinter();
        if (tokenMinter != CCTP_TOKEN_MINTER_V2) {
            revert InvalidCCTPMinter(tokenMinter, CCTP_TOKEN_MINTER_V2);
        }

        _approveToken(token, messenger, 0);
        _approveToken(token, messenger, amount);

        ITokenMessengerV2(messenger).depositForBurn(
            amount,
            0,
            mintRecipient,
            token,
            mintRecipient,
            maxFee,
            minFinalityThreshold
        );

        emit CCTPDepositForBurn(token, 0, mintRecipient, amount);
    }

    function _lighterDepositTokenToThis(uint16 assetIndex, uint8 routeType, uint256 amount) internal {
        if (amount == 0) {
            revert InvalidLighterAmount(amount);
        }

        address lighter = zkLighter();
        address token = lighterAssetToken(assetIndex);
        if (token == address(0)) {
            revert InvalidLighterToken(assetIndex, token);
        }
        _validateLighterRoute(assetIndex, routeType);

        _approveToken(token, lighter, 0);
        _approveToken(token, lighter, amount);

        IZkLighter(lighter).deposit(address(this), assetIndex, routeType, amount);

        _approveToken(token, lighter, 0);
        emit LighterDeposit(address(this), assetIndex, routeType, amount);
    }

    function _lighterDepositAllTokenToThis(uint16 assetIndex, uint8 routeType) internal returns (uint256 amount) {
        address token = lighterAssetToken(assetIndex);
        if (token == address(0)) {
            revert InvalidLighterToken(assetIndex, token);
        }

        amount = _tokenBalance(token);
        _lighterDepositTokenToThis(assetIndex, routeType, amount);
    }

    function _lighterWithdraw(uint48 accountIndex, uint16 assetIndex, uint8 routeType, uint64 baseAmount) internal {
        if (baseAmount == 0) {
            revert InvalidLighterAmount(baseAmount);
        }
        _validateLighterRoute(assetIndex, routeType);

        IZkLighter(zkLighter()).withdraw(accountIndex, assetIndex, routeType, baseAmount);
        emit LighterWithdraw(accountIndex, assetIndex, routeType, baseAmount);
    }

    function _validateLighterRoute(uint16 assetIndex, uint8 routeType) internal view {
        uint16 usdcAssetIndex = IZkLighter(zkLighter()).USDC_ASSET_INDEX();
        if (routeType > LIGHTER_ROUTE_SPOT || (routeType == LIGHTER_ROUTE_PERPS && assetIndex != usdcAssetIndex)) {
            revert InvalidLighterRoute(assetIndex, routeType);
        }
    }

    function _lighterWithdrawPendingBalanceToThis(uint16 assetIndex, uint128 baseAmount) internal {
        if (baseAmount == 0) {
            revert InvalidLighterAmount(baseAmount);
        }

        IZkLighter(zkLighter()).withdrawPendingBalance(address(this), assetIndex, baseAmount);
        emit LighterPendingBalanceWithdrawn(address(this), assetIndex, baseAmount);
    }

    function _lighterWithdrawAllPendingBalanceToThis(uint16 assetIndex) internal returns (uint128 amount) {
        IZkLighter lighter = IZkLighter(zkLighter());
        amount = lighter.getPendingBalance(address(this), assetIndex);
        if (amount == 0) {
            revert InvalidLighterAmount(amount);
        }

        lighter.withdrawPendingBalance(address(this), assetIndex, amount);
        emit LighterPendingBalanceWithdrawn(address(this), assetIndex, amount);
    }

    function _approveToken(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenWithdrawFailed(token, spender, amount);
        }
    }

    function _addressToBytes32(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    function _flushTokenIfPresent(address token) internal returns (bool flushed) {
        uint256 amount = _tokenBalance(token);
        if (amount == 0) {
            return false;
        }

        _withdrawToken(token, ETH_FORWARD_RECIPIENT, amount);
        return true;
    }

    function _unwrapWETH(uint256 amount) internal {
        address token = weth();
        IWETH(token).withdraw(amount);
        _withdrawEther(ETH_FORWARD_RECIPIENT, amount);
        emit WETHUnwrapped(token, ETH_FORWARD_RECIPIENT, amount);
    }

    function _tokenBalance(address token) internal view returns (uint256 amount) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        if (!ok || data.length < 32) {
            return 0;
        }

        amount = abi.decode(data, (uint256));
    }

    function _ethereumTopToken(uint256 index) internal pure returns (address) {
        if (index == 0) return ETHEREUM_USDC;
        if (index == 1) return 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        if (index == 2) return ETHEREUM_WETH;
        if (index == 3) return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        if (index == 4) return 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        if (index == 5) return 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        if (index == 6) return 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        if (index == 7) return 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        if (index == 8) return 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        return 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO
    }

    function _baseTopToken(uint256 index) internal pure returns (address) {
        if (index == 0) return BASE_USDC;
        if (index == 1) return BASE_WETH;
        if (index == 2) return 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbBTC
        if (index == 3) return 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22; // cbETH
        if (index == 4) return 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb; // DAI
        if (index == 5) return 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // USDbC
        if (index == 6) return 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // AERO
        if (index == 7) return 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; // VIRTUAL
        if (index == 8) return 0x532f27101965dd16442E59d40670FaF5eBB142E4; // BRETT
        return 0xbAA5c2bfDCCda47E8F2C8c5cc6c4dD5849237f7D; // MORPHO
    }

    function _arbitrumTopToken(uint256 index) internal pure returns (address) {
        if (index == 0) return ARBITRUM_USDC;
        if (index == 1) return 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC.e
        if (index == 2) return 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        if (index == 3) return ARBITRUM_WETH;
        if (index == 4) return 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        if (index == 5) return 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
        if (index == 6) return 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        if (index == 7) return 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4; // LINK
        if (index == 8) return 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a; // GMX
        return 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F; // FRAX
    }

    function _optimismTopToken(uint256 index) internal pure returns (address) {
        if (index == 0) return OPTIMISM_USDC;
        if (index == 1) return 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // USDC.e
        if (index == 2) return 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58; // USDT
        if (index == 3) return OPTIMISM_WETH;
        if (index == 4) return 0x4200000000000000000000000000000000000042; // OP
        if (index == 5) return 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
        if (index == 6) return 0x68f180fcCe6836688e9084f035309E29Bf0A2095; // WBTC
        if (index == 7) return 0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6; // LINK
        if (index == 8) return 0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4; // SNX
        return 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db; // VELO
    }

    function _forwardEther(address payable recipient, uint256 amount) internal {
        _sendEther(recipient, amount);
        emit EtherForwarded(msg.sender, recipient, amount);
    }

    function _sendEther(address payable recipient, uint256 amount) internal {
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) {
            revert WithdrawFailed(recipient, amount);
        }
    }
}
