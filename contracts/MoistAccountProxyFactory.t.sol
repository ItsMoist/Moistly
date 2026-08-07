// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MoistAccountProxy} from "./MoistAccountProxy.sol";
import {MoistAccountProxyFactory} from "./MoistAccountProxyFactory.sol";

contract ProxyTestImplementation {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

contract MoistAccountProxyFactoryTest is Test {
    MoistAccountProxyFactory internal factory;
    ProxyTestImplementation internal implementation;
    address internal owner = address(0xBEEF);

    function setUp() public {
        factory = new MoistAccountProxyFactory();
        implementation = new ProxyTestImplementation();
    }

    function test_SaltIsOwnerAndNonceDerived() public view {
        bytes32 expected = keccak256(
            abi.encode(factory.DOMAIN_SALT(), owner, uint256(7))
        );
        assertEq(factory.saltFor(owner, 7), expected);
    }

    function test_PredictionMatchesDeployment() public {
        bytes memory initData = abi.encodeCall(ProxyTestImplementation.setValue, (123));
        address predicted = factory.predictAddress(owner, 0, address(implementation), initData);

        vm.prank(owner);
        address deployed = factory.deployAtNonce(0, address(implementation), initData);

        assertEq(deployed, predicted);
        assertEq(ProxyTestImplementation(deployed).value(), 123);
        assertTrue(factory.nonceUsed(owner, 0));
    }

    function test_ExplicitHighNonceDoesNotBurnLowerNonce() public {
        bytes memory initData;

        vm.prank(owner);
        address high = factory.deployAtNonce(5, address(implementation), initData);

        assertTrue(high != address(0));
        assertEq(factory.nextNonce(owner), 0);
        assertFalse(factory.nonceUsed(owner, 0));

        address predictedZero = factory.predictAddress(owner, 0, address(implementation), initData);
        vm.prank(owner);
        address zero = factory.deployNext(address(implementation), initData);

        assertEq(zero, predictedZero);
        assertEq(factory.nextNonce(owner), 1);
    }

    function test_DeployNextSkipsExplicitlyConsumedNonce() public {
        bytes memory initData;

        vm.prank(owner);
        factory.deployAtNonce(0, address(implementation), initData);
        assertEq(factory.nextNonce(owner), 1);

        vm.prank(owner);
        factory.deployAtNonce(2, address(implementation), initData);
        assertEq(factory.nextNonce(owner), 1);

        address predictedOne = factory.predictAddress(owner, 1, address(implementation), initData);
        vm.prank(owner);
        address one = factory.deployNext(address(implementation), initData);

        assertEq(one, predictedOne);
        assertEq(factory.nextNonce(owner), 3);
    }

    function test_ReusingNonceReverts() public {
        bytes memory initData;

        vm.prank(owner);
        factory.deployAtNonce(11, address(implementation), initData);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MoistAccountProxyFactory.NonceAlreadyConsumed.selector, owner, uint256(11))
        );
        factory.deployAtNonce(11, address(implementation), initData);
    }
}
