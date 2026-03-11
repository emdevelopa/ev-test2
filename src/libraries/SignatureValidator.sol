// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library SignatureValidator {
    bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    
    bytes32 constant AUTHORIZATION_TYPEHASH = keccak256(
        "Authorize(uint256 proposalId,uint256 nonce)"
    );

    function getDomainSeparator(string memory name, string memory version, address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
    }
    
    function recoverSigner(bytes32 domainSeparator, uint256 proposalId, uint256 nonce, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, proposalId, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        address recoveredAddress = ecrecover(digest, v, r, s);
        return recoveredAddress;
    }
}
