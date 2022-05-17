// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./IHyperXNFTFactory.sol";
import "./ContractInterface.sol";

contract HyperXNFTFactory is IHyperXNFTFactory, Ownable, ReentrancyGuard {
    using Address for address;

    struct HyperXNFTSale {
        uint256 saleId;
        address creator;
        address seller;
        address sc;
        uint256 tokenId;
        uint256 copy;
        uint256 payment;
        uint256 basePrice;
        uint256 method;
        uint256 startTime;
        uint256 endTime;
        uint256 feeRatio;
        uint256 royaltyRatio;
        address buyer;
    }

    struct BidInfo {
        address user;
        uint256 price;
    }

    enum METHOD_TYPE { DIRECT_SALE, AUCTION, UNLISTED }
    enum PAYMENT { BNB, BUSD, HYPERX }

    /**
     * delay period to add a creator to the list
     */
    uint256 public DELAY_PERIOD = 3 seconds;

    /**
     * deployer for single/multiple NFT collection
     */
    address private singleDeployer;
    address private multipleDeployer;

    /**
     * array of collection addresses including ERC721 and ERC1155
     */
    address[] private collections;
    /**
     * check if the collection has already been added to this factory
     */
    mapping(address => bool) collectionOccupation;

    /**
     * token address for payment
     */
    address[] private paymentTokens;

    /**
     * check if it is the creator permitted by owner(admin)
     */
    mapping(address => bool) private creators;
    /**
     * epoch timestamp of starting the process that permits one account to be a creator
     */
    mapping(address => uint256) private pendingTime;
    /**
     * pending value that presents the creator is enabled/disabled by true/false
     */
    mapping(address => bool) private pendingValue;

    /**
     * saleId => (address => bidPrice)
     */
    mapping(uint256 => BidInfo[]) public map_bidInfoList;

    /**
     * default fee value set by owner of the contract, defaultFeeRatio / 10000 is the real ratio.
     */
    uint256 public defaultFeeRatio;

    /**
     * default royalty value set by owner of the contract, defaultRoyaltyRatio / 10000 is the real ratio.
     */
    uint256 public defaultRoyaltyRatio;

    /**
     * dev address
     */
    address public devAddress;

    /**
     * sale list by its created index
     */
    mapping(uint256 => HyperXNFTSale) public saleList;

    /**
     * unlistedAmount[collection address][token ID][owner address]
     */
    struct UnlistedInfo {
        uint256 amount;
        bool    isUpdated;
    }
    mapping(address => mapping(uint256 => mapping(address => UnlistedInfo))) public unlistedInfo;

    /**
     * sale list count or future index to be created
     */
    uint256 public saleCount;

    /**
     * event that marks the creator has been permitted by an owner(admin)
     */
    event SetCreatorForFactory(address account, bool set);

    /**
     * event when an owner sets default fee ratio
     */
    event SetDefaultFeeRatio(address owner, uint256 newFeeRatio);

    /**
     * event when an owner sets default royalty ratio
     */
    event SetDefaultRoyaltyRatio(address owner, uint256 newRoyaltyRatio);

    /**
     * event when a new payment token set
     */
    event PaymentTokenSet(uint256 id, address indexed tokenAddress);

    /**
     * event when a new ERC721 contract is created.
     * Do not remove this event even if it is not used.
     */
    event ERC721TradableContractCreated(
        string name, 
        address indexed contractAddress,
        address indexed creator
    );

    /**
     * event when a new ERC1155 contract is created.
     * Do not remove this event even if it is not used.
     */
    event ERC1155TradableContractCreated(
        string name, 
        address indexed contractAddress,
        address indexed creator
    );

    /**
     * event when an seller lists his/her token on sale
     */

    event ListedOnSale(
        uint256 saleId,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a seller cancels his sale
     */
    event SaleRemoved(
        uint256 saleId,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a user makes an offer for unlisted NFTs
     */

    event OfferMade(
        address indexed user,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a user makes an offer for fixed-price sale
     */
    event Buy(
        address indexed user,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a user places a bid for timed-auction sale
     */
    event BidPlaced(
        address indexed user,
        uint256 bidPrice,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a user places a bid for timed-auction sale
     */
    event BidRemoved(
        address indexed user,
        HyperXNFTSale saleInfo
    );

    /**
     * event when a trade is successfully made.
     */

    event Traded(
        HyperXNFTSale sale,
        uint256 amount,
        uint256 when
    );

    /**
     * event when deployers are updated
     */
    event UpdateDeployers(
        address indexed singleCollectionDeployer,
        address indexed multipleCollectionDeployer
    );

    /**
     * event when NFT are transferred
     */
    event TransferNFTs(
        address from,
        address to,
        address collection,
        uint256[] ids,
        uint256[] amounts
    );

    /**
     * this modifier restricts some privileged action
     */
    modifier creatorOnly() {
        // address ms = msg.sender;
        // require(ms == owner() || creators[ms] == true, "neither owner nor creator");
        _;
    }

    /**
     * constructor of the factory does not have parameters
     */
    constructor(
        address singleCollectionDeployer,
        address multipleCollectionDeployer
    ) {
        paymentTokens.push(address(0)); // native currency
        
        setDefaultFeeRatio(250);
        setDefaultRoyaltyRatio(300);
        updateDeployers(singleCollectionDeployer, multipleCollectionDeployer);
    }

    /**
     * @dev this function updates the deployers for ERC721, ERC1155
     * @param singleCollectionDeployer - deployer for ERC721
     * @param multipleCollectionDeployer - deployer for ERC1155
     */

    function updateDeployers(
        address singleCollectionDeployer,
        address multipleCollectionDeployer
    ) public onlyOwner {
        singleDeployer = singleCollectionDeployer;
        multipleDeployer = multipleCollectionDeployer;

        emit UpdateDeployers(singleCollectionDeployer, multipleCollectionDeployer);
    }

    /**
     * This function modifies or adds a new payment token
     */
    function setPaymentToken(uint256 tId, address tokenAddr) public onlyOwner {
        // IERC165(tokenAddr).supportsInterface(type(IERC20).interfaceId);
        require(tokenAddr != address(0), "null address for payment token");

        if (tId >= paymentTokens.length ) {
            tId = paymentTokens.length;
            paymentTokens.push(tokenAddr);
        } else {
            require(tId < paymentTokens.length, "invalid payment token id");
            paymentTokens[tId] = tokenAddr;
        }

        emit PaymentTokenSet(tId, tokenAddr);
    }

    /**
     * This function gets token addresses for payment
     */
    function getPaymentToken() public view returns (address[] memory) {
        return paymentTokens;
    }

    /**
     * start the process of adding a creator to be enabled/disabled
     */
    function startPendingCreator(address account, bool set) external onlyOwner {
        require(pendingTime[account] == 0);

        pendingTime[account] = block.timestamp;
        pendingValue[account] = set;
    }

    /**
     * end the process of adding a creator to be enabled/disabled
     */
    function endPendingCreator(address account) external onlyOwner {
        require((pendingTime[account] + DELAY_PERIOD) < block.timestamp);

        bool curVal = pendingValue[account];
        creators[account] = curVal;
        pendingTime[account] = 0;

        emit SetCreatorForFactory(account, curVal);
    }

    /**
     * update a creator to be enabled/disabled
     */
    function updateCreatorStatus(address _addr, bool _isEnabled) external onlyOwner {
      creators[_addr] = _isEnabled;
    }

    /**
     * set developer address
     */
    function setDevAddr(address addr) public onlyOwner {
        devAddress = addr;
    }

    /**
     * @dev this function creates a new collection of ERC721, ERC1155 to the factory
     * @param collectionType - ERC721 = 0, ERC1155 = 1
     * @param _name - collection name
     * @param _symbol - collection symbol
     * @param _uri - base uri of NFT token metadata
     */
    function createNewCollection(
        IHyperXNFTFactory.CollectionType collectionType,
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) external creatorOnly override returns (address) {
        if (collectionType == IHyperXNFTFactory.CollectionType.ERC721) {
            // create a new ERC721 contract and returns its address
            address newContract = IContractInterface721(singleDeployer).createContract(_name, _symbol, _uri, address(this));

            require(collectionOccupation[newContract] == false);

            collections.push(newContract);
            collectionOccupation[newContract] = true;

            Ownable(newContract).transferOwnership(msg.sender);

            emit ERC721TradableContractCreated(_name, newContract, msg.sender);
            return newContract;
        } else if (collectionType == IHyperXNFTFactory.CollectionType.ERC1155) {
            // create a new ERC1155 contract and returns its address
            address newContract = IContractInterface1155(multipleDeployer).createContract(_name, _symbol, _uri, address(this));

            require(collectionOccupation[newContract] == false);

            collections.push(newContract);
            collectionOccupation[newContract] = true;

            Ownable(newContract).transferOwnership(msg.sender);

            emit ERC1155TradableContractCreated(_name, newContract, msg.sender);
            return newContract;
        } else revert("Unknown collection contract");
    }

    /**
     * @dev this function adds a collection of ERC721, ERC1155 to the factory
     * @param from - address of NFT collection contract
     */
    function addCollection(address from) external creatorOnly override {
        require(from.isContract());

        if (IERC165(from).supportsInterface(type(IERC721).interfaceId)) {
            require(collectionOccupation[from] == false);

            collections.push(from);
            collectionOccupation[from] = true;

            emit CollectionAdded(IHyperXNFTFactory.CollectionType.ERC721, from);
        } else if (
            IERC165(from).supportsInterface(type(IERC1155).interfaceId)
        ) {
            require(collectionOccupation[from] == false);

            collections.push(from);
            collectionOccupation[from] = true;

            emit CollectionAdded(
                IHyperXNFTFactory.CollectionType.ERC1155,
                from
            );
        } else {
            revert("Error adding unknown NFT collection");
        }
    }

    /**
     * @dev this function transfers NFTs of 'sc' from account 'from' to account 'to' for token ids 'ids'
     * @param sc - address of NFT collection contract
     * @param from - owner of NFTs at the moment
     * @param to - future owner of NFTs
     * @param ids - array of token id to be transferred
     * @param amounts - array of token amount to be transferred
     */
    function transferNFT(
        address sc,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal {
        require(collectionOccupation[sc] == true);

        if (IERC165(sc).supportsInterface(type(IERC721).interfaceId)) {
            // ERC721 transfer, amounts has no meaning in this case
            uint256 i;
            bytes memory nbytes = new bytes(0);
            for (i = 0; i < ids.length; i++) {
                IERC721(sc).safeTransferFrom(from, to, ids[i], nbytes);
            }
        } else if (IERC165(sc).supportsInterface(type(IERC1155).interfaceId)) {
            // ERC1155 transfer
            bytes memory nbytes = new bytes(0);
            IERC1155(sc).safeBatchTransferFrom(from, to, ids, amounts, nbytes);
        }

        emit TransferNFTs(from, to, sc, ids, amounts);
    }

    /**
     * @dev this function retrieves array of all collections registered to the factory
     */
    function getCollections()
        public
        view
        returns (address[] memory)
    {
        return collections;
    }

    /**
     * @dev this function sets default fee ratio.
     */
    function setDefaultFeeRatio(uint256 newFeeRatio) public onlyOwner {
        defaultFeeRatio = newFeeRatio;
        emit SetDefaultFeeRatio(owner(), newFeeRatio);
    }

    /**
     * @dev this function sets default royalty ratio.
     */
    function setDefaultRoyaltyRatio(uint256 newRoyaltyRatio) public onlyOwner {
        defaultRoyaltyRatio = newRoyaltyRatio;
        emit SetDefaultRoyaltyRatio(owner(), newRoyaltyRatio);
    }

    /**
     * @dev this function returns URI string by checking its ERC721 or ERC1155 type.
     */
    function getURIString(address sc, uint256 tokenId)
        internal
        view
        returns (string memory uri, uint256 sc_type)
    {
        if (IERC165(sc).supportsInterface(type(IERC721).interfaceId)) {
            uri = IContractInfoWrapper(sc).tokenURI(tokenId);
            sc_type = 1;
        } else if (IERC165(sc).supportsInterface(type(IERC1155).interfaceId)) {
            uri = IContractInfoWrapper(sc).uri(tokenId);
            sc_type = 2;
        } else sc_type = 0;
    }

    /**
     * @dev get balance of token a holder owns
     */
    function balanceOf(address sc, address holder, uint256 tokenId) public view returns (uint256) {
        uint256 balance = 0;
        if (IERC165(sc).supportsInterface(type(IERC721).interfaceId)) {
            balance = IERC721(sc).balanceOf(holder);
        } else if (IERC165(sc).supportsInterface(type(IERC1155).interfaceId)) {
            balance = IERC1155(sc).balanceOf(holder, tokenId);
        }

        return balance;
    }

    /*
     * update an unlisted amount of a token the holder owns
     */
    function updateUnlistedAmount(address sc, uint256 tokenId, address holder, uint256 detaAmt, bool isPlus) public {
        uint256 balance = balanceOf(sc, holder, tokenId);
        require(balance > 0, "No Balance!");

        UnlistedInfo storage curInfo = unlistedInfo[sc][tokenId][holder];
        if (!curInfo.isUpdated) {
            require(!isPlus && balance >= detaAmt, "Invalid detaAmt parameter - 0");

            curInfo.amount = balance - detaAmt;
            curInfo.isUpdated = true;
            return;
        }

        require((!isPlus && curInfo.amount >= detaAmt) || (isPlus && curInfo.amount + detaAmt <= balance), "Invalid detaAmt parameter - 1");
        
        curInfo.amount = (isPlus)? curInfo.amount + detaAmt : curInfo.amount - detaAmt;
    }

    function getUnlistedAmount(address sc, uint256 tokenId, address holder) public view returns (uint256) {
        UnlistedInfo memory curInfo = unlistedInfo[sc][tokenId][holder];

        return (curInfo.isUpdated)? curInfo.amount : balanceOf(sc, holder, tokenId);
    }

    /**
     * @dev this function sets default royalty ratio.
     * @param sc - address of NFT collection contract
     * @param tokenId - token index in 'sc'
     * @param payment - payment method for buyer/bidder/offerer/auctioner, 0: BNB, 1: BUSD, 2: HyperX, ...
     * @param method - 0: Direct Sale, 1: Auction
     * @param duration - duration of sale in seconds
     * @param basePrice - price in 'payment' coin
     * @param royaltyRatio - royalty ratio (1/10000) for transaction
     */
    function createSale(
        address sc,
        uint256 tokenId,
        uint256 payment,
        uint256 copy,
        uint256 method,
        uint256 duration,
        uint256 basePrice,
        uint256 royaltyRatio
    ) public {
        require(method == uint256(METHOD_TYPE.DIRECT_SALE) || method == uint256(METHOD_TYPE.AUCTION), "Invalid method!");
        if (method == uint256(METHOD_TYPE.AUCTION))
            require(copy == 1, "Only 1 Auction is possible.");
        require(duration > 0, "Duration should be over than zero(0)");

        address creator = address(0);

        (, uint256 sc_type) = getURIString(sc, tokenId);
        if (sc_type == 1) {
            require(IERC721(sc).ownerOf(tokenId) == msg.sender, "not owner of the ERC721 token to be on sale");
            require(copy == 1, "ERC721 token sale amount is not 1");
            creator = IContractInfoWrapper(sc).getCreator(tokenId);
        } else if (sc_type == 2) {
            require(getUnlistedAmount(sc, tokenId, msg.sender) >= copy && copy > 0, "exceeded the Unlisted amount to be on sale");
            creator = IContractInfoWrapper(sc).getCreator(tokenId);
        } else revert("Not supported NFT contract");

        uint256 curSaleIndex = saleCount;
        saleCount++;

        HyperXNFTSale storage hxns = saleList[curSaleIndex];
        hxns.saleId = curSaleIndex;
        hxns.creator = creator;
        hxns.seller = msg.sender;
        hxns.sc = sc;
        hxns.tokenId = tokenId;
        hxns.copy = copy;
        hxns.payment = payment;
        hxns.basePrice = basePrice;
        hxns.method = method;
        hxns.startTime = block.timestamp;
        hxns.endTime = block.timestamp + duration;
        hxns.feeRatio = defaultFeeRatio;
        hxns.royaltyRatio = (royaltyRatio == 0)? defaultRoyaltyRatio : royaltyRatio;

        updateUnlistedAmount(sc, tokenId, msg.sender, copy, false);

        emit ListedOnSale(curSaleIndex, hxns);
    }

    /**
     * @dev this function removes an existing sale
     * @param saleId - index of the sale
     */
    function removeSale(uint256 saleId) external {
        HyperXNFTSale storage hxns = saleList[saleId];

        require(msg.sender == hxns.seller || msg.sender == owner(), "unprivileged remove");
        require(hxns.method == uint256(METHOD_TYPE.DIRECT_SALE), "for Auction, removing is impossible!");

        updateUnlistedAmount(hxns.sc, hxns.tokenId, hxns.seller, hxns.copy, true);
        _removeSale(saleId);
    }

    /**
     * @dev this function removes an existing sale
     * @param saleId - index of the sale
     */
    function _removeSale(uint256 saleId) internal {
        HyperXNFTSale storage hxns = saleList[saleId];
        hxns.startTime = 0;
        hxns.endTime = 0;

        emit SaleRemoved(saleId, hxns);
    }

    /**
     * @dev this function returns validity of the sale
     * @param saleId - index of the sale
     */
    function isSaleValid(uint256 saleId) public view returns (bool) {
        if (saleId >= saleCount) return false;
        HyperXNFTSale storage hxns = saleList[saleId];

        return (hxns.startTime != 0 && hxns.endTime != 0);
    }

    /**
     * @dev this function lets a buyer buy NFTs on sale
     * @param saleId - index of the sale
     * @param amount - amount of NFTs to buy
     */
    function buy(uint256 saleId, uint256 amount) public payable nonReentrant {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        require(hxns.startTime <= block.timestamp && hxns.endTime >= block.timestamp, "sale time is not invalid.");
        require(hxns.method == uint256(METHOD_TYPE.DIRECT_SALE), "offer not for fixed-price sale");
        require(msg.sender != hxns.seller, "Seller is not allowed to buy his NFT");
        require(amount > 0 && amount <= hxns.copy, "Amount to buy would exceed Copy.");

        uint256 salePrice = amount * hxns.basePrice;
        if (hxns.payment == uint256(PAYMENT.BNB)) {
            require(msg.value >= salePrice, "Insufficient funds!");
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            tokenInst.transferFrom(msg.sender, address(this), salePrice);
        }

        hxns.buyer = msg.sender;
        trade(saleId, salePrice, amount);
    }

    /**
     * @dev this function places a bid from a user
     * @param saleId - index of the sale
     * @param bidPrice - index of the sale
     */
    function placeBid(uint256 saleId, uint256 bidPrice) public payable nonReentrant {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        require(hxns.startTime <= block.timestamp && hxns.endTime >= block.timestamp, "Invalid Bid time!");
        require(hxns.method == uint256(METHOD_TYPE.AUCTION), "bid not for timed-auction sale");
        require(msg.sender != hxns.seller, "Seller is not allowed to place a bid on his NFT");
        require(bidPrice >= hxns.copy * hxns.basePrice, "Invalid a bid price!");

        BidInfo[] storage biList = map_bidInfoList[saleId];

        bool isBidded = false;
        uint256 prevPrice = 0;

        for (uint256 i=0; i<biList.length; i++) {
            if (biList[i].user == msg.sender) {
                prevPrice = biList[i].price;
                biList[i].price = bidPrice;

                isBidded = true;
                break;
            }
        }

        if (!isBidded) {
            BidInfo memory bi = BidInfo(msg.sender, bidPrice);
            biList.push(bi);
        }
        
        if (hxns.payment == uint256(PAYMENT.BNB)) {
            require(msg.value >= bidPrice, "Insufficient native currency for bid");
            if (isBidded)
                payable(msg.sender).transfer(prevPrice);
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            if (isBidded)
                tokenInst.transfer(msg.sender, prevPrice);
            
            tokenInst.transferFrom(msg.sender, address(this), bidPrice);
        }

        emit BidPlaced(msg.sender, bidPrice, hxns);
    }

    function removeBid(uint256 saleId) external payable nonReentrant {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        require(hxns.method == uint256(METHOD_TYPE.AUCTION), "bid not for timed-auction sale");

        BidInfo[] storage biList = map_bidInfoList[saleId];

        bool isBidded = false;
        uint256 bidIdx = 0;
        for (uint256 i=0; i<biList.length; i++) {
            if (biList[i].user == msg.sender) {
                bidIdx = i;

                isBidded = true;
                break;
            }
        }

        require(isBidded, "No bid!");
        require(biList[bidIdx].user == msg.sender, "You should become a buyer.");

        // refund
        if (hxns.payment == uint256(PAYMENT.BNB)) {
            payable(biList[bidIdx].user).transfer(biList[bidIdx].price);
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            tokenInst.transfer(biList[bidIdx].user, biList[bidIdx].price);
        }

        // remove bidInfo
        biList[bidIdx] = biList[biList.length - 1];
        biList.pop();

        emit BidRemoved(msg.sender, hxns);
    }

    /**
     * @dev this function puts an end to timed-auction sale
     * @param saleId - index of the sale of timed-auction
     */
    function _finalizeAuction(uint256 saleId) internal {
        HyperXNFTSale storage hxns = saleList[saleId];

        BidInfo[] storage biList = map_bidInfoList[saleId];

        // winning to the highest bid
        uint256 maxPrice = 0;
        uint256 bidId = 0;

        for (uint256 i = 0; i < biList.length; i++) {
            BidInfo memory bi = biList[i];
            if (maxPrice < bi.price) {
                maxPrice = bi.price;
                bidId = i;
            }
        }

        if (biList.length == 0 || maxPrice == 0) {
            updateUnlistedAmount(hxns.sc, hxns.tokenId, hxns.seller, hxns.copy, true);
            _removeSale(saleId);

            return;
        }

        // refund
        for (uint256 i = 0; i < biList.length; i++) {
            if (i != bidId) {
                BidInfo memory bi = biList[i];

                if (hxns.payment == uint256(PAYMENT.BNB)) {
                    payable(bi.user).transfer(bi.price);
                } else {
                    IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
                    tokenInst.transfer(bi.user, bi.price);
                }
            }
        }

        hxns.basePrice = biList[bidId].price;
        hxns.buyer = biList[bidId].user;
        trade(saleId, hxns.copy * hxns.basePrice, hxns.copy);
    }

    /**
     * @dev this function sets default royalty ratio.
     * @param sc - address of NFT collection contract
     * @param tokenId - token index in 'sc'
     * @param payment - payment method for buyer/bidder/offerer/auctioner, 0: BNB, 1: BUSD, 2: HyperX, ...
     * @param duration - duration of sale in seconds
     * @param unitPrice - price in 'payment' coin
     */
    function makeOffer(
        address sc,
        uint256 tokenId,
        address owner,
        uint256 copy,
        uint256 payment,
        uint256 unitPrice,
        uint256 duration
    ) public payable nonReentrant{
        require(msg.sender != owner, "Owner is not allowed to make an offer on his NFT");

        address creator = address(0);

        (, uint256 sc_type) = getURIString(sc, tokenId);
        if (sc_type == 1) {
            require(IERC721(sc).ownerOf(tokenId) == owner, "invalid owner of the ERC721 token to be offered");
            creator = IContractInfoWrapper(sc).getCreator(tokenId);
        } else if (sc_type == 2) {
            require(copy > 0 && copy <= getUnlistedAmount(sc, tokenId, owner), "exceeded amount of ERC1155 token to be on sale");
            creator = IContractInfoWrapper(sc).getCreator(tokenId);
        } else revert("Not supported NFT contract");

        uint256 curSaleIndex = saleCount;
        saleCount++;

        HyperXNFTSale storage hxns = saleList[curSaleIndex];
        hxns.saleId = curSaleIndex;
        hxns.creator = creator;
        hxns.seller = owner;
        hxns.buyer = msg.sender;
        hxns.sc = sc;
        hxns.tokenId = tokenId;
        hxns.copy = copy;
        hxns.payment = payment;
        hxns.basePrice = unitPrice;
        hxns.method = uint256(METHOD_TYPE.UNLISTED);
        hxns.startTime = block.timestamp;
        hxns.endTime = block.timestamp + duration;
        hxns.feeRatio = defaultFeeRatio;
        hxns.royaltyRatio = defaultRoyaltyRatio;

        uint256 salePrice = hxns.copy * hxns.basePrice;

        if (hxns.payment == uint256(PAYMENT.BNB)) {
            require(msg.value >= salePrice, "insufficient native currency to buy");
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            tokenInst.transferFrom(msg.sender, address(this), salePrice);
        }

        emit OfferMade(msg.sender, hxns);
    }

    /**
     * @dev this function puts an end to offer sale
     * @param saleId - index of the sale of offer
     */
    function acceptOffer(uint256 saleId) public payable nonReentrant {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        require(hxns.startTime <= block.timestamp && block.timestamp <= hxns.endTime, "Invalid offer time!");
        require(hxns.method == uint256(METHOD_TYPE.UNLISTED), "not sale for offer");
        require(hxns.seller == msg.sender, "only seller can accept offer for his NFT");

        uint256 unlistedAmt = getUnlistedAmount(hxns.sc, hxns.tokenId, hxns.seller);

        uint256 tradedAmt = hxns.copy;
        if (unlistedAmt < hxns.copy) {
            tradedAmt = unlistedAmt;

            // refund
            uint256 refundedAmt = hxns.copy - unlistedAmt;
            if (hxns.payment == uint256(PAYMENT.BNB)) {
                payable(hxns.buyer).transfer(refundedAmt * hxns.basePrice);
            } else {
                IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
                tokenInst.transfer(hxns.buyer, refundedAmt * hxns.basePrice);
            }
        }

        updateUnlistedAmount(hxns.sc, hxns.tokenId, hxns.seller, tradedAmt, false);
        trade(saleId, tradedAmt * hxns.basePrice, tradedAmt);
    }

    /**
     * @dev this function removes an offer
     * @param saleId - index of the sale of offer
     */
    function removeOffer(uint256 saleId) public payable nonReentrant {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        require(hxns.buyer == msg.sender || owner() == msg.sender, "only offerer can remove an offer");
        require(hxns.method == uint256(METHOD_TYPE.UNLISTED), "not sale for offer");

        _removeOffer(saleId);        
    }

    function _removeOffer(uint256 saleId) internal {
        HyperXNFTSale storage hxns = saleList[saleId];

        if (hxns.payment == uint256(PAYMENT.BNB)) {
            payable(hxns.buyer).transfer(hxns.copy * hxns.basePrice);
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            tokenInst.transfer(hxns.buyer, hxns.copy * hxns.basePrice);
        }

        _removeSale(saleId);
    }

    /**
     * @dev this function transfers NFTs from the seller to the buyer
     * @param saleId - index of the sale to be treated
     * @param salePrice - totla price for Sale
     * @param amount - index of the booked winner on a sale
     */
    function trade(uint256 saleId, uint256 salePrice, uint256 amount) internal {
        require(isSaleValid(saleId), "sale is not valid");

        HyperXNFTSale storage hxns = saleList[saleId];

        uint256 serviceFee = salePrice * defaultFeeRatio / 10000;
        uint256 royalty = salePrice * hxns.royaltyRatio / 10000;
        uint256 devFee = (devAddress == address(0))? 0 : (salePrice * 10) / 10000;
        
        uint256 sellerPay = salePrice - serviceFee - royalty;

        if (hxns.payment == uint256(PAYMENT.BNB)) {
            payable(hxns.seller).transfer(sellerPay);

            if (royalty > 0)
                payable(hxns.creator).transfer(royalty);

            if (devFee > 0)
                payable(devAddress).transfer(devFee);
        } else {
            IERC20 tokenInst = IERC20(paymentTokens[hxns.payment]);
            tokenInst.transfer(hxns.seller, sellerPay);

            if (royalty > 0)
                tokenInst.transfer(hxns.creator, royalty);

            if (devFee > 0)
                tokenInst.transfer(devAddress, devFee);
        }

        uint256[] memory ids = new uint256[](1);
        ids[0] = hxns.tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        transferNFT(hxns.sc, hxns.seller, hxns.buyer, ids, amounts);

        hxns.copy -= amount;

        emit Traded(hxns, amount, block.timestamp);

        if (hxns.copy == 0 || hxns.method == uint256(METHOD_TYPE.UNLISTED))
            _removeSale(saleId);
    }

    /**
     * @dev this function processes all items on timed sale
     * @param idList - ID list of timed sales
     */
    function processTimedSales(uint256[] memory idList) external onlyOwner {
        for (uint256 i=0; i<idList.length; i++) {
            uint256 saleId = idList[i];

            HyperXNFTSale memory hxns = saleList[saleId];
            if (!isSaleValid(saleId) || hxns.endTime >= block.timestamp) continue;

            // process for timed Sales
            if (hxns.method == uint256(METHOD_TYPE.DIRECT_SALE)) {
                updateUnlistedAmount(hxns.sc, hxns.tokenId, hxns.seller, hxns.copy, true);
                _removeSale(saleId);
            } else if (hxns.method == uint256(METHOD_TYPE.AUCTION)) {
                _finalizeAuction(saleId);
            } else if (hxns.method == uint256(METHOD_TYPE.UNLISTED)) {
                _removeOffer(saleId);
            }
        }
    }

    function getTimedSales(uint256 startIdx, uint256 count) external onlyOwner view returns (HyperXNFTSale[] memory) {
        uint256 endIdx = startIdx + count;
        require(endIdx <= saleCount, "Invalid parameter");

        uint256 realCount = 0;
        for (uint256 i=startIdx; i<endIdx; i++) {
            if (!isSaleValid(i) || saleList[i].endTime >= block.timestamp) continue;

            realCount ++;
        }

        HyperXNFTSale[] memory ret = new HyperXNFTSale[](realCount);

        uint256 nPos = 0;
        for (uint256 i=startIdx; i<endIdx; i++) {
            HyperXNFTSale memory sale = saleList[i];
            if (!isSaleValid(i) || sale.endTime >= block.timestamp) continue;

            ret[nPos] = sale;
            nPos++;
        }

        return ret;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);
    }
}
