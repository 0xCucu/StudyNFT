// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

abstract contract ERC721Study is Ownable, ERC721Enumerable {
    string private _contractURI;
    string private _tokenBaseURI;
    address proxyRegistryAddress;

    constructor() {}


    function setProxyRegistryAddress(address proxyAddress) external onlyOwner {
        proxyRegistryAddress = proxyAddress;
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Whitelist OpenSea proxy contract for easy trading.
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        if (address(proxyRegistry.proxies(owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    function setContractURI(string calldata URI) external onlyOwner {
        _contractURI = URI;
    }

    // To support Opensea contract-level metadata
    // https://docs.opensea.io/docs/contract-level-metadata
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setBaseURI(string calldata URI) external onlyOwner {
        _tokenBaseURI = URI;
    }

    // To support Opensea token metadata
    // https://docs.opensea.io/docs/metadata-standards
    function _baseURI()
        internal
        view
        override(ERC721)
        returns (string memory)
    {
        return _tokenBaseURI;
    }
}


contract PreSalesActivation is Ownable {
    uint256 public preSalesStartTime;
    uint256 public preSalesEndTime;

    modifier isPreSalesActive() {
        require(
            isPreSalesActivated(),
            "PreSalesActivation: Sale is not activated"
        );
        _;
    }

    constructor() {}

    function isPreSalesActivated() public view returns (bool) {
        return
            preSalesStartTime > 0 &&
            preSalesEndTime > 0 &&
            block.timestamp >= preSalesStartTime &&
            block.timestamp <= preSalesEndTime;
    }

    // 1643983200: start time at 04 Feb 2022 (2 PM UTC+0) in seconds
    // 1644026400: end time at 05 Feb 2022 (2 AM UTC+0) in seconds
    function setPreSalesTime(uint256 _startTime, uint256 _endTime)
        external
        onlyOwner
    {
        require(
            _endTime >= _startTime,
            "PreSalesActivation: End time should be later than start time"
        );
        preSalesStartTime = _startTime;
        preSalesEndTime = _endTime;
    }
}
contract PublicSalesActivation is Ownable {
    uint256 public publicSalesStartTime;

    modifier isPublicSalesActive() {
        require(
            isPublicSalesActivated(),
            "PublicSalesActivation: Sale is not activated"
        );
        _;
    }

    constructor() {}

    function isPublicSalesActivated() public view returns (bool) {
        return
            publicSalesStartTime > 0 && block.timestamp >= publicSalesStartTime;
    }

    // 1644069600: start time at 05 Feb 2022 (2 PM UTC+0) in seconds
    function setPublicSalesTime(uint256 _startTime) external onlyOwner {
        publicSalesStartTime = _startTime;
    }
}
contract Whitelist is Ownable, EIP712 {
    bytes32 public constant WHITELIST_TYPEHASH =
        keccak256("Whitelist(address buyer,uint256 signedQty,uint256 nonce)");
    address public whitelistSigner;

    modifier isSenderWhitelisted(
        uint256 _signedQty,
        uint256 _nonce,
        bytes memory _signature
    ) {
        require(
            getSigner(msg.sender, _signedQty, _nonce, _signature) ==
                whitelistSigner,
            "Whitelist: Invalid signature"
        );
        _;
    }

    constructor(string memory name, string memory version)
        EIP712(name, version)
    {}

    function setWhitelistSigner(address _address) external onlyOwner {
        whitelistSigner = _address;
    }

    function getSigner(
        address _buyer,
        uint256 _signedQty,
        uint256 _nonce,
        bytes memory _signature
    ) public view returns (address) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(WHITELIST_TYPEHASH, _buyer, _signedQty, _nonce)
            )
        );
        return ECDSA.recover(digest, _signature);
    }
}
contract Withdrawable is Ownable {
    constructor() {}

    function withdrawAll() external onlyOwner {
        require(address(this).balance > 0, "Withdrawble: No amount to withdraw");
        payable(msg.sender).transfer(address(this).balance);
    }
}
contract StaudyNFT is
    Ownable,
    ERC721Study,
    PreSalesActivation,
    PublicSalesActivation,
    Whitelist,
    
    Withdrawable
{
    uint256 public constant TOTAL_MAX_QTY = 5555;
    uint256 public constant GIFT_MAX_QTY = 133;
    uint256 public constant PRESALES_MAX_QTY = 3500;
    uint256 public constant SALES_MAX_QTY = TOTAL_MAX_QTY - GIFT_MAX_QTY;
    uint256 public constant MAX_QTY_PER_MINTER = 2;
    uint256 public constant PRE_SALES_PRICE = 0.2 ether;
    uint256 public constant PUBLIC_SALES_START_PRICE = 0.5 ether;

    uint256 public constant priceDropDuration = 600; // 10 mins
    uint256 public constant priceDropAmount = 0.025 ether;
    uint256 public constant priceDropFloor = 0.2 ether;

    mapping(address => uint256) public preSalesMinterToTokenQty;
    mapping(address => uint256) public publicSalesMinterToTokenQty;

    uint256 public preSalesMintedQty = 0;
    uint256 public publicSalesMintedQty = 0;
    uint256 public giftedQty = 0;

    constructor() ERC721("StudyNFT", "SNFT") Whitelist("StudyNFT", "1") {}

    function getPrice() public view returns (uint256) {
        // Public sales
        if (isPublicSalesActivated()) {
            uint256 dropCount = (block.timestamp - publicSalesStartTime) /
                priceDropDuration;
            // It takes 12 dropCount to reach at 0.2 floor price in Dutch Auction
            return
                dropCount < 12
                    ? PUBLIC_SALES_START_PRICE - dropCount * priceDropAmount
                    : priceDropFloor;
        }
        return PRE_SALES_PRICE;
    }

    function preSalesMint(
        uint256 _mintQty,
        uint256 _signedQty,
        uint256 _nonce,
        bytes memory _signature
    )
        external
        payable
        isPreSalesActive
        isSenderWhitelisted(_signedQty, _nonce, _signature)
    {
        require(
            preSalesMintedQty + publicSalesMintedQty + _mintQty <=
                SALES_MAX_QTY,
            "Exceed sales max limit"
        );
        require(
            preSalesMintedQty + _mintQty <= PRESALES_MAX_QTY,
            "Exceed pre-sales max limit"
        );
        require(
            preSalesMinterToTokenQty[msg.sender] + _mintQty <= _signedQty,
            "Exceed signed quantity"
        );
        require(msg.value >= _mintQty * getPrice(), "Insufficient ETH");
        require(tx.origin == msg.sender, "Contracts not allowed");

        preSalesMinterToTokenQty[msg.sender] += _mintQty;
        preSalesMintedQty += _mintQty;

        for (uint256 i = 0; i < _mintQty; i++) {
            _safeMint(msg.sender, totalSupply() + 1);
        }
    }

    function publicSalesMint(uint256 _mintQty)
        external
        payable
        isPublicSalesActive
    {
        require(
            preSalesMintedQty + publicSalesMintedQty + _mintQty <=
                SALES_MAX_QTY,
            "Exceed sales max limit"
        );
        require(
            publicSalesMinterToTokenQty[msg.sender] + _mintQty <=
                MAX_QTY_PER_MINTER,
            "Exceed max mint per minter"
        );
        require(msg.value >= _mintQty * getPrice(), "Insufficient ETH");
        require(tx.origin == msg.sender, "Contracts not allowed");

        publicSalesMinterToTokenQty[msg.sender] += _mintQty;
        publicSalesMintedQty += _mintQty;

        for (uint256 i = 0; i < _mintQty; i++) {
            _safeMint(msg.sender, totalSupply() + 1);
        }
    }

    function gift(address[] calldata receivers) external onlyOwner {
        require(
            giftedQty + receivers.length <= GIFT_MAX_QTY,
            "Exceed gift max limit"
        );

        giftedQty += receivers.length;

        for (uint256 i = 0; i < receivers.length; i++) {
            _safeMint(receivers[i], totalSupply() + 1);
        }
    }
}