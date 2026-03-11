// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/core/AresTreasury.sol";
import "../src/core/AresTimelockExecution.sol";
import "../src/modules/AresProposalManager.sol";
import "../src/modules/AresAuthorization.sol";
import "../src/modules/AresRewards.sol";
import "./MockToken.sol";
import "../src/libraries/SignatureValidator.sol";

contract MaliciousContract {
    AresTimelockExecution public timelock;
    bytes32 public proposalId;
    address public target;
    uint256 public value;
    bytes public callData;

    constructor(AresTimelockExecution _timelock) {
        timelock = _timelock;
    }

    function setParams(bytes32 _proposalId, address _target, uint256 _value, bytes memory _data) external {
        proposalId = _proposalId;
        target = _target;
        value = _value;
        callData = _data;
    }

    fallback() external payable {
        if (msg.sender == target) {
         
            timelock.executeProposal(proposalId, target, value, callData);
        }
    }
}

contract AresProtocolTest is Test {
    AresTreasury treasury;
    AresTimelockExecution timelock;
    AresProposalManager proposalManager;
    AresAuthorization authorization;
    AresRewards rewards;
    MockToken govToken;
    MockToken rewardToken;
    
    address authorizer;
    uint256 authorizerPk;
    
    address proposer;
    address user1;
    address user2;
    
    uint256 constant DELAY = 2 days;
    uint256 constant THRESHOLD = 100_000 * 10**18;
    uint256 constant DRAIN_LIMIT = 1000 ether;
    uint256 constant EPOCH = 7 days;
    
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        (authorizer, authorizerPk) = makeAddrAndKey("authorizer");
        proposer = makeAddr("proposer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        govToken = new MockToken();
        rewardToken = new MockToken();
        
   
        address authAddr = computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        address testTimelockAddr = computeCreateAddress(address(this), vm.getNonce(address(this)));
        
        // Timelock
        timelock = new AresTimelockExecution(DELAY, authAddr); 
        require(address(timelock) == testTimelockAddr, "Timelock addr mismatch");
        
        // Proposal Manager
        proposalManager = new AresProposalManager(address(govToken), THRESHOLD); 
        
        // Treasury
        treasury = new AresTreasury(address(timelock), DRAIN_LIMIT, EPOCH); 
        
        // Authorization
        authorization = new AresAuthorization(address(timelock), address(proposalManager), authorizer);
        require(address(authorization) == authAddr, "Auth addr mismatch");
        
        // Rewards
        rewards = new AresRewards(address(rewardToken), address(treasury));
        
        // Fund Treasury
        vm.deal(address(treasury), 10000 ether);
        
        // Fund Proposer
        govToken.mint(proposer, 500_000 * 10**18);
        
        DOMAIN_SEPARATOR = authorization.DOMAIN_SEPARATOR();
    }

    function test_Functional_Lifecycle() public {
        vm.startPrank(proposer);
        
        address target = address(user1);
        uint256 value = 1 ether;
        bytes memory data = "";
        
      
        bytes memory execData = abi.encodeWithSelector(treasury.executeTransaction.selector, target, value, data);
        uint256 propId = proposalManager.propose(address(treasury), 0, execData);
        vm.stopPrank();
        
    
        uint256 nonce = authorization.nonces(authorizer);
        bytes32 structHash = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), propId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        
        authorization.authorizeProposal(propId, v, r, s);
        
        bytes32 globalId = keccak256(abi.encodePacked(propId, address(authorization)));
        
       
        vm.warp(block.timestamp + DELAY + 1);
        
        uint256 balBefore = user1.balance;
      
        timelock.executeProposal(globalId, address(treasury), 0, execData);
        
        assertEq(user1.balance, balBefore + 1 ether);
    }
    
    function test_Functional_RewardClaim() public {
        bytes32[] memory proof = new bytes32[](1);
    
        bytes32 leaf0 = keccak256(abi.encodePacked(uint256(0), user1, uint256(100)));
        bytes32 leaf1 = keccak256(abi.encodePacked(uint256(1), user2, uint256(200)));
        
        bytes32 root;
        if (leaf0 <= leaf1) {
            root = keccak256(abi.encodePacked(leaf0, leaf1));
            proof[0] = leaf1;
        } else {
            root = keccak256(abi.encodePacked(leaf1, leaf0));
            proof[0] = leaf1;
        }
        
        vm.prank(address(treasury));
        rewards.updateRoot(root);
        
        rewardToken.mint(address(rewards), 1000);
        
        vm.prank(user1);
        rewards.claim(0, 100, proof);
        
        assertEq(rewardToken.balanceOf(user1), 100);
    }

    // Malicious contract reentrancy
    function test_Exploit_Reentrancy() public {
        MaliciousContract malicious = new MaliciousContract(timelock);
        bytes memory execData = abi.encodeWithSelector(treasury.executeTransaction.selector, address(malicious), 1 ether, "");
        
        vm.prank(proposer);
        uint256 propId = proposalManager.propose(address(treasury), 0, execData);
        
        uint256 nonce = authorization.nonces(authorizer);
        bytes32 structHash = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), propId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        
        authorization.authorizeProposal(propId, v, r, s);
        
        bytes32 globalId = keccak256(abi.encodePacked(propId, address(authorization)));
        
        malicious.setParams(globalId, address(treasury), 0, execData);
        
        vm.warp(block.timestamp + DELAY + 1);
        
        vm.deal(address(timelock), 10 ether); 
        
        // Reentrancy should fail
        vm.expectRevert();
        timelock.executeProposal(globalId, address(treasury), 0, execData);
    }

   
    function test_Exploit_DoubleClaim() public {
        bytes32[] memory proof = new bytes32[](1);
        bytes32 leaf0 = keccak256(abi.encodePacked(uint256(0), user1, uint256(100)));
        bytes32 leaf1 = keccak256(abi.encodePacked(uint256(1), user2, uint256(200)));
        
        bytes32 root;
        if (leaf0 <= leaf1) {
            root = keccak256(abi.encodePacked(leaf0, leaf1));
            proof[0] = leaf1;
        } else {
            root = keccak256(abi.encodePacked(leaf1, leaf0));
            proof[0] = leaf1;
        }
        
        vm.prank(address(treasury));
        rewards.updateRoot(root);
        rewardToken.mint(address(rewards), 1000);
        
        vm.prank(user1);
        rewards.claim(0, 100, proof);
        
        vm.prank(user1);
        vm.expectRevert(AresRewards.AlreadyClaimed.selector);
        rewards.claim(0, 100, proof);
    }
    
    // Invalid signature
    function test_Exploit_InvalidSignature() public {
        bytes memory execData = abi.encodeWithSelector(treasury.executeTransaction.selector, user1, 1 ether, "");
        vm.prank(proposer);
        uint256 propId = proposalManager.propose(address(treasury), 0, execData);
        
        uint256 nonce = authorization.nonces(authorizer);
        bytes32 structHash = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), propId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        
       
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(12345, digest);
        
        vm.expectRevert(AresAuthorization.InvalidSignature.selector);
        authorization.authorizeProposal(propId, v, r, s);
    }

  
    function test_Exploit_PrematureExecution() public {
        bytes memory execData = abi.encodeWithSelector(treasury.executeTransaction.selector, user1, 1 ether, "");
        vm.prank(proposer);
        uint256 propId = proposalManager.propose(address(treasury), 0, execData);
        
        uint256 nonce = authorization.nonces(authorizer);
        bytes32 structHash = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), propId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        
        authorization.authorizeProposal(propId, v, r, s);
        bytes32 globalId = keccak256(abi.encodePacked(propId, address(authorization)));
        
        // executing before DELAY
        vm.expectRevert(AresTimelockExecution.TimelockNotExpired.selector);
        timelock.executeProposal(globalId, address(treasury), 0, execData);
    }
    
    // Proposal replay
    function test_Exploit_ProposalReplay() public {
        bytes memory execData = abi.encodeWithSelector(treasury.executeTransaction.selector, user1, 1 ether, "");
        vm.prank(proposer);
        uint256 propId = proposalManager.propose(address(treasury), 0, execData);
        
        uint256 nonce = authorization.nonces(authorizer);
        bytes32 structHash = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), propId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        
        authorization.authorizeProposal(propId, v, r, s);
        
        // Replay same signature - should fail due to nonce
        vm.expectRevert(AresAuthorization.AlreadyAuthorized.selector);
        authorization.authorizeProposal(propId, v, r, s);
        
        bytes32 globalId = keccak256(abi.encodePacked(propId, address(authorization)));
        
        vm.warp(block.timestamp + DELAY + 1);
        timelock.executeProposal(globalId, address(treasury), 0, execData);
        
        // Try executing again
        vm.expectRevert(AresTimelockExecution.InvalidState.selector);
        timelock.executeProposal(globalId, address(treasury), 0, execData);
    }

    // Unauthorized execution of timelock
    function test_Exploit_UnauthorizedExecution() public {
        bytes32 fakeGlobalId = keccak256("fake");
        vm.expectRevert(AresTimelockExecution.OnlyAuthorizationModule.selector);
        timelock.queueProposal(fakeGlobalId, address(treasury), 0, "");
    }

    function test_Exploit_MaxDrainLimit() public {
        bytes32 gid1;
        bytes32 gid2;
        bytes memory execData1 = abi.encodeWithSelector(treasury.executeTransaction.selector, user1, 600 ether, "");
        bytes memory execData2 = abi.encodeWithSelector(treasury.executeTransaction.selector, user2, 600 ether, "");
        
        {
            vm.startPrank(proposer);
            uint256 prop1 = proposalManager.propose(address(treasury), 0, execData1);
            vm.stopPrank();
            
            bytes32 sh1 = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), prop1, authorization.nonces(authorizer)));
            bytes32 d1 = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, sh1));
            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(authorizerPk, d1);
            authorization.authorizeProposal(prop1, v1, r1, s1);
            gid1 = keccak256(abi.encodePacked(prop1, address(authorization)));
        }
        
        {
            vm.startPrank(proposer);
            uint256 prop2 = proposalManager.propose(address(treasury), 0, execData2);
            vm.stopPrank();
            
            bytes32 sh2 = keccak256(abi.encode(keccak256("Authorize(uint256 proposalId,uint256 nonce)"), prop2, authorization.nonces(authorizer)));
            bytes32 d2 = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, sh2));
            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(authorizerPk, d2);
            authorization.authorizeProposal(prop2, v2, r2, s2);
            gid2 = keccak256(abi.encodePacked(prop2, address(authorization)));
        }
        
        vm.warp(block.timestamp + DELAY + 1);
        
        timelock.executeProposal(gid1, address(treasury), 0, execData1);
        
        vm.expectRevert();
        timelock.executeProposal(gid2, address(treasury), 0, execData2);
    }
    
    // Proposal Threshold Bypass
    function test_Exploit_ProposalThresholdBypass() public {
        vm.prank(user1); 
        vm.expectRevert(AresProposalManager.BelowProposalThreshold.selector);
        proposalManager.propose(user1, 1 ether, "");
    }
}
