// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC3009} from "../../src/interfaces/IERC3009.sol";
import {IMulticall3} from "../../src/interfaces/IMulticall3.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {PermitHash} from "permit2/libraries/PermitHash.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {PublicERC6492Validator} from "spend-permissions/PublicERC6492Validator.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {MockERC3009Token} from "../mocks/MockERC3009Token.sol";
import {DeployPermit2} from "permit2/../test/utils/DeployPermit2.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {ERC3009PaymentCollector} from "../../src/collectors/ERC3009PaymentCollector.sol";
import {PreApprovalPaymentCollector} from "../../src/collectors/PreApprovalPaymentCollector.sol";
import {Permit2PaymentCollector} from "../../src/collectors/Permit2PaymentCollector.sol";
import {SpendPermissionPaymentCollector} from "../../src/collectors/SpendPermissionPaymentCollector.sol";
import {OperatorRefundCollector} from "../../src/collectors/OperatorRefundCollector.sol";
import {ERC20UnsafeTransferTokenCollector} from "../../test/mocks/ERC20UnsafeTransferTokenCollector.sol";

contract PaymentEscrowBase is Test, DeployPermit2 {
    using PermitHash for ISignatureTransfer.PermitTransferFrom;

    // Enum to make it easier to reference hooks in tests
    enum TokenCollector {
        ERC3009,
        ERC20,
        Permit2,
        SpendPermission,
        OperatorRefund,
        ERC20UnsafeTransfer
    }

    PaymentEscrow public paymentEscrow;
    MockERC3009Token public mockERC3009Token;
    MockERC20 public mockERC20Token;
    address public multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public permit2;
    SpendPermissionManager public spendPermissionManager;
    PublicERC6492Validator public publicERC6592Validator;
    MagicSpend public magicSpend;

    // TokenCollector contracts
    ERC3009PaymentCollector public erc3009Hook;
    PreApprovalPaymentCollector public erc20Hook;
    Permit2PaymentCollector public permit2Hook;
    SpendPermissionPaymentCollector public spendPermissionHook;
    OperatorRefundCollector public operatorRefundCollector;
    ERC20UnsafeTransferTokenCollector public erc20UnsafeTransferHook;

    // Mapping to store token collector addresses
    mapping(TokenCollector => address) public hooks;

    uint256 public magicSpendOwnerPk = 0xC014BA53;
    address public magicSpendOwner;
    address public operator;
    address public receiver;
    address public payerEOA;
    address public feeReceiver;
    uint16 constant FEE_BPS = 100; // 1%
    uint256 internal constant payer_EOA_PK = 0x1234;

    bytes32 constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    constructor() DeployPermit2() {}

    function setUp() public virtual {
        // set up Multicall3
        vm.etch(
            0xcA11bde05977b3631167028862bE2a173976CA11,
            hex"6080604052600436106100f35760003560e01c80634d2301cc1161008a578063a8b0574e11610059578063a8b0574e1461025a578063bce38bd714610275578063c3077fa914610288578063ee82ac5e1461029b57600080fd5b80634d2301cc146101ec57806372425d9d1461022157806382ad56cb1461023457806386d516e81461024757600080fd5b80633408e470116100c65780633408e47014610191578063399542e9146101a45780633e64a696146101c657806342cbb15c146101d957600080fd5b80630f28c97d146100f8578063174dea711461011a578063252dba421461013a57806327e86d6e1461015b575b600080fd5b34801561010457600080fd5b50425b6040519081526020015b60405180910390f35b61012d610128366004610a85565b6102ba565b6040516101119190610bbe565b61014d610148366004610a85565b6104ef565b604051610111929190610bd8565b34801561016757600080fd5b50437fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0140610107565b34801561019d57600080fd5b5046610107565b6101b76101b2366004610c60565b610690565b60405161011193929190610cba565b3480156101d257600080fd5b5048610107565b3480156101e557600080fd5b5043610107565b3480156101f857600080fd5b50610107610207366004610ce2565b73ffffffffffffffffffffffffffffffffffffffff163190565b34801561022d57600080fd5b5044610107565b61012d610242366004610a85565b6106ab565b34801561025357600080fd5b5045610107565b34801561026657600080fd5b50604051418152602001610111565b61012d610283366004610c60565b61085a565b6101b7610296366004610a85565b610a1a565b3480156102a757600080fd5b506101076102b6366004610d18565b4090565b60606000828067ffffffffffffffff8111156102d8576102d8610d31565b60405190808252806020026020018201604052801561031e57816020015b6040805180820190915260008152606060208201528152602001906001900390816102f65790505b5092503660005b8281101561047757600085828151811061034157610341610d60565b6020026020010151905087878381811061035d5761035d610d60565b905060200281019061036f9190610d8f565b6040810135958601959093506103886020850185610ce2565b73ffffffffffffffffffffffffffffffffffffffff16816103ac6060870187610dcd565b6040516103ba929190610e32565b60006040518083038185875af1925050503d80600081146103f7576040519150601f19603f3d011682016040523d82523d6000602084013e6103fc565b606091505b50602080850191909152901515808452908501351761046d577f08c379a000000000000000000000000000000000000000000000000000000000600052602060045260176024527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060445260846000fd5b5050600101610325565b508234146104e6576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601a60248201527f4d756c746963616c6c333a2076616c7565206d69736d6174636800000000000060448201526064015b60405180910390fd5b50505092915050565b436060828067ffffffffffffffff81111561050c5761050c610d31565b60405190808252806020026020018201604052801561053f57816020015b606081526020019060019003908161052a5790505b5091503660005b8281101561068657600087878381811061056257610562610d60565b90506020028101906105749190610e42565b92506105836020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff166105a66020850185610dcd565b6040516105b4929190610e32565b6000604051808303816000865af19150503d80600081146105f1576040519150601f19603f3d011682016040523d82523d6000602084013e6105f6565b606091505b5086848151811061060957610609610d60565b602090810291909101015290508061067d576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601760248201527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060448201526064016104dd565b50600101610546565b5050509250929050565b43804060606106a086868661085a565b905093509350939050565b6060818067ffffffffffffffff8111156106c7576106c7610d31565b60405190808252806020026020018201604052801561070d57816020015b6040805180820190915260008152606060208201528152602001906001900390816106e55790505b5091503660005b828110156104e657600084828151811061073057610730610d60565b6020026020010151905086868381811061074c5761074c610d60565b905060200281019061075e9190610e76565b925061076d6020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff166107906040850185610dcd565b60405161079e929190610e32565b6000604051808303816000865af19150503d80600081146107db576040519150601f19603f3d011682016040523d82523d6000602084013e6107e0565b606091505b506020808401919091529015158083529084013517610851577f08c379a000000000000000000000000000000000000000000000000000000000600052602060045260176024527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060445260646000fd5b50600101610714565b6060818067ffffffffffffffff81111561087657610876610d31565b6040519080825280602002602001820160405280156108bc57816020015b6040805180820190915260008152606060208201528152602001906001900390816108945790505b5091503660005b82811015610a105760008482815181106108df576108df610d60565b602002602001015190508686838181106108fb576108fb610d60565b905060200281019061090d9190610e42565b925061091c6020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff1661093f6020850185610dcd565b60405161094d929190610e32565b6000604051808303816000865af19150503d806000811461098a576040519150601f19603f3d011682016040523d82523d6000602084013e61098f565b606091505b506020830152151581528715610a07578051610a07576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601760248201527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060448201526064016104dd565b506001016108c3565b5050509392505050565b6000806060610a2b60018686610690565b919790965090945092505050565b60008083601f840112610a4b57600080fd5b50813567ffffffffffffffff811115610a6357600080fd5b6020830191508360208260051b8501011115610a7e57600080fd5b9250929050565b60008060208385031215610a9857600080fd5b823567ffffffffffffffff811115610aaf57600080fd5b610abb85828601610a39565b90969095509350505050565b6000815180845260005b81811015610aed57602081850181015186830182015201610ad1565b81811115610aff576000602083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0169290920160200192915050565b600082825180855260208086019550808260051b84010181860160005b84811015610bb1578583037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe001895281518051151584528401516040858501819052610b9d81860183610ac7565b9a86019a9450505090830190600101610b4f565b5090979650505050505050565b602081526000610bd16020830184610b32565b9392505050565b600060408201848352602060408185015281855180845260608601915060608160051b870101935082870160005b82811015610c52577fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa0888703018452610c40868351610ac7565b95509284019290840190600101610c06565b509398975050505050505050565b600080600060408486031215610c7557600080fd5b83358015158114610c8557600080fd5b9250602084013567ffffffffffffffff811115610ca157600080fd5b610cad86828701610a39565b9497909650939450505050565b838152826020820152606060408201526000610cd96060830184610b32565b95945050505050565b600060208284031215610cf457600080fd5b813573ffffffffffffffffffffffffffffffffffffffff81168114610bd157600080fd5b600060208284031215610d2a57600080fd5b5035919050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b7f4e487b7100000000000000000000000000000000000000000000000000000000600052603260045260246000fd5b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff81833603018112610dc357600080fd5b9190910192915050565b60008083357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe1843603018112610e0257600080fd5b83018035915067ffffffffffffffff821115610e1d57600080fd5b602001915036819003821315610a7e57600080fd5b8183823760009101908152919050565b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc1833603018112610dc357600080fd5b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa1833603018112610dc357600080fdfea2646970667358221220bb2b5c71a328032f97c676ae39a1ec2148d3e5d6f73d95e9b17910152d61f16264736f6c634300080c0033"
        );

        // deploy token and permit2
        mockERC3009Token = new MockERC3009Token("Mock USDC", "mUSDC", 6);
        mockERC20Token = new MockERC20("Mock USDC", "mUSDC", 6);
        permit2 = address(deployPermit2());
        publicERC6592Validator = new PublicERC6492Validator();

        magicSpendOwner = vm.addr(magicSpendOwnerPk);
        magicSpend = new MagicSpend(magicSpendOwner, 1); // (owner, maxWithdrawDenominator)
        spendPermissionManager = new SpendPermissionManager(publicERC6592Validator, address(magicSpend));

        // Deploy PaymentEscrow
        paymentEscrow = new PaymentEscrow();

        // Deploy token collector contracts
        erc3009Hook = new ERC3009PaymentCollector(address(paymentEscrow), multicall3);
        erc20Hook = new PreApprovalPaymentCollector(address(paymentEscrow));
        permit2Hook = new Permit2PaymentCollector(address(paymentEscrow), permit2);
        spendPermissionHook =
            new SpendPermissionPaymentCollector(address(paymentEscrow), address(spendPermissionManager));
        operatorRefundCollector = new OperatorRefundCollector(address(paymentEscrow));
        erc20UnsafeTransferHook = new ERC20UnsafeTransferTokenCollector(address(paymentEscrow));

        // Store token collector addresses in mapping
        hooks[TokenCollector.ERC3009] = address(erc3009Hook);
        hooks[TokenCollector.ERC20] = address(erc20Hook);
        hooks[TokenCollector.Permit2] = address(permit2Hook);
        hooks[TokenCollector.SpendPermission] = address(spendPermissionHook);
        hooks[TokenCollector.OperatorRefund] = address(operatorRefundCollector);
        hooks[TokenCollector.ERC20UnsafeTransfer] = address(erc20UnsafeTransferHook);

        // Setup roles
        operator = vm.addr(1);
        vm.label(operator, "operator");
        receiver = vm.addr(2);
        vm.label(receiver, "receiver");
        payerEOA = vm.addr(payer_EOA_PK);
        feeReceiver = vm.addr(4);
        vm.label(feeReceiver, "feeReceiver");

        // Mint tokens to payer
        mockERC3009Token.mint(payerEOA, 1000e9);
    }

    function _createPaymentEscrowAuthorization(address payer, uint120 maxAmount)
        internal
        view
        returns (PaymentEscrow.PaymentInfo memory)
    {
        return _createPaymentEscrowAuthorization(payer, maxAmount, address(mockERC3009Token));
    }

    function _createPaymentEscrowAuthorization(address payer, uint120 maxAmount, address token)
        internal
        view
        returns (PaymentEscrow.PaymentInfo memory)
    {
        return PaymentEscrow.PaymentInfo({
            operator: operator,
            payer: payer,
            receiver: receiver,
            token: token,
            maxAmount: maxAmount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: FEE_BPS,
            maxFeeBps: FEE_BPS,
            feeReceiver: feeReceiver,
            salt: 0
        });
    }

    function _signPaymentInfo(PaymentEscrow.PaymentInfo memory paymentInfo, uint256 signerPk)
        internal
        view
        returns (bytes memory)
    {
        address payer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 nonce = paymentEscrow.getHash(paymentInfo);
        paymentInfo.payer = payer;

        bytes32 digest = _getERC3009Digest(
            payer, hooks[TokenCollector.ERC3009], paymentInfo.maxAmount, 0, paymentInfo.preApprovalExpiry, nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getERC3009Digest(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                mockERC3009Token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(), from, to, value, validAfter, validBefore, nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", mockERC3009Token.DOMAIN_SEPARATOR(), structHash));
    }

    function _signPermit2Transfer(address token, uint256 amount, uint256 deadline, uint256 nonce, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        // Create PermitTransferFrom struct
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
            nonce: nonce,
            deadline: deadline
        });

        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount));
        bytes32 permitHash = keccak256(
            abi.encode(
                _PERMIT_TRANSFER_FROM_TYPEHASH,
                tokenPermissionsHash,
                hooks[TokenCollector.Permit2],
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 domainSeparator = IPermit2(permit2).DOMAIN_SEPARATOR();

        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }
}
