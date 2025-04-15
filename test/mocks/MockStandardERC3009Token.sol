// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";

contract MockStandardERC3009Token is ERC20 {
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    // Only implement the standard v,r,s version
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(to == msg.sender, "MockStandardERC3009: caller must be the payee");
        require(!_authorizationStates[from][nonce], "MockStandardERC3009: authorization is used");
        require(block.timestamp > validAfter, "MockStandardERC3009: authorization not yet valid");
        require(block.timestamp < validBefore, "MockStandardERC3009: authorization expired");

        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        require(ecrecover(digest, v, r, s) == from, "MockStandardERC3009: invalid signature");

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    function _constantNameHash() internal pure override returns (bytes32) {
        return keccak256(bytes("Mock Standard ERC3009 Token"));
    }

    function _constantVersionHash() internal pure returns (bytes32) {
        return keccak256(bytes("2"));
    }
}
