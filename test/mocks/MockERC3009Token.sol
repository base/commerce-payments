// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IERC3009} from "../../src/interfaces/IERC3009.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

contract MockERC3009Token is ERC20, IERC3009 {
    // Same constants as USDC implementation
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

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

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        require(to == msg.sender, "MockERC3009: caller must be the payee");
        require(!_authorizationStates[from][nonce], "MockERC3009: authorization is used");
        require(block.timestamp > validAfter, "MockERC3009: authorization not yet valid");
        require(block.timestamp < validBefore, "MockERC3009: authorization expired");

        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        require(SignatureCheckerLib.isValidSignatureNow(from, digest, signature), "MockERC3009: invalid signature");

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

    // Override ERC20's domain name and version
    function _constantNameHash() internal pure override returns (bytes32) {
        return keccak256(bytes("USD Coin"));
    }

    function _constantVersionHash() internal pure returns (bytes32) {
        return keccak256(bytes("2"));
    }

    event Debug(string name, bytes32 value);
    event Debug(string name, address value);
}
