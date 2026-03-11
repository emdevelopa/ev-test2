// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IAresTreasury.sol";

// This contract holds the funds and enforces global limits.
contract AresTreasury is IAresTreasury {
    address public immutable timelock;
    uint256 public maxDrainPerEpoch;
    uint256 public epochDuration;
    
    mapping(uint256 => uint256) public epochOutflow;
    
    event TransactionExecuted(address indexed target, uint256 value, bytes data);
    event FundsReceived(address indexed sender, uint256 amount);
    event DrainLimitUpdated(uint256 newLimit);
    
    error OnlyTimelock();
    error DrainLimitExceeded();
    error CallFailed();

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock();
        _;
    }

    constructor(address _timelock, uint256 _maxDrainPerEpoch, uint256 _epochDuration) {
        timelock = _timelock;
        maxDrainPerEpoch = _maxDrainPerEpoch;
        epochDuration = _epochDuration;
    }

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
    function receiveFunds() external payable override {
        emit FundsReceived(msg.sender, msg.value);
    }

    function executeTransaction(address target, uint256 value, bytes calldata data) external override onlyTimelock returns (bytes memory) {
        uint256 currentEpoch = block.timestamp / epochDuration;
        
        if (epochOutflow[currentEpoch] + value > maxDrainPerEpoch) {
            revert DrainLimitExceeded();
        }
        
        epochOutflow[currentEpoch] += value;
        
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        if (!success) {
            revert CallFailed();
        }
        
        emit TransactionExecuted(target, value, data);
        return returnData;
    }
    
    function updateDrainLimit(uint256 newLimit) external override onlyTimelock {
        maxDrainPerEpoch = newLimit;
        emit DrainLimitUpdated(newLimit);
    }
}
