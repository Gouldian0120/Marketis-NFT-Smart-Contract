// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Marketis is ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using CountersUpgradeable for CountersUpgradeable.Counter;
  CountersUpgradeable.Counter private _tokenIds;

  mapping(address => bool) public excludedList;
  mapping(uint256 => TokenMeta) private _tokenMeta;

  string private baseURI;
  uint256 private feeCreateTokens;
  uint256 private feeSellTokens;
  uint256 private maxAllowedRoyalties;
  address private txFeeToken;

  struct TokenMeta {
    uint256 id;
    uint256 price;
    uint256 royalty;
    string name;
    bool sale;
    address artist;
  }

  function initialize() public initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    ERC721Upgradeable.__ERC721_init('Marketis', 'MTIS');
    setBaseURI('https://marketis.devmitsoftware.com/token?id=');
    // NRT smart contract address
    txFeeToken = 0x376495a6878A0E2B142c6bf5c0D29Fee785df5c9;
    // address excluded to pay fees on transfer NFT
    excludedList[owner()] = true;
    // 2.5 %
    feeCreateTokens = 250;
    // 10 %
    maxAllowedRoyalties = 1000;
    // 2.5 %
    feeSellTokens = 250;
  }

  /**
   * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
   * in child contracts.
   */
  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }

  function setTxFeeToken(address _newTxFeeToken) public virtual onlyOwner {
    txFeeToken = _newTxFeeToken;
  }

  function setBaseURI(string memory _newBaseURI) public virtual onlyOwner {
    baseURI = _newBaseURI;
  }

  function setFeeCreateTokens(uint256 _newFeeCreateTokens) public onlyOwner {
    feeCreateTokens = _newFeeCreateTokens;
  }

  function getFeeCreateToken() public view returns (uint256) {
    return feeCreateTokens;
  }

  function setFeeSellTokens(uint256 _newFeeSellTokens) public onlyOwner {
    feeSellTokens = _newFeeSellTokens;
  }

  function getFeeSellTokens() public view returns (uint256) {
    return feeSellTokens;
  }

  /**
   * @dev sets max allowed royalty to create a new token
   * @param _newMaxAllowedRoyalties uint256 max value %
   */
  function setMaxAllowedRoyalties(uint256 _newMaxAllowedRoyalties) public onlyOwner {
    require(_newMaxAllowedRoyalties < 5000, 'ERC721: Max Allowed Royalties 50%');
    maxAllowedRoyalties = _newMaxAllowedRoyalties;
  }

  function getAllOnSale() public view virtual returns (TokenMeta[] memory) {
    TokenMeta[] memory tokensOnSale = new TokenMeta[](_tokenIds.current());
    uint256 counter = 0;

    for (uint256 i = 1; i < _tokenIds.current() + 1; i++) {
      if (_tokenMeta[i].sale == true) {
        tokensOnSale[counter] = _tokenMeta[i];
        counter++;
      }
    }
    return tokensOnSale;
  }

  /**
   * @dev sets maps token to its price
   * @param _tokenId uint256 token ID (token number)
   * @param _sale bool token on sale
   * @param _price unit256 token price
   *
   * Requirements:
   * `tokenId` must exist
   * `price` must be more than 0
   * `owner` must the msg.owner
   */
  function setTokenSale(
    uint256 _tokenId,
    bool _sale,
    uint256 _price
  ) public {
    require(_exists(_tokenId), 'ERC721: Sale set of nonexistent token');
    require(_price > 0, 'ERC721: Price of token must be greater than zero');
    require(ownerOf(_tokenId) == _msgSender(), 'ERC721: Only owner of token can do this action');

    _tokenMeta[_tokenId].sale = _sale;
    setTokenPrice(_tokenId, _price);
  }

  /**
   * @dev sets maps token to its price
   * @param _tokenId uint256 token ID (token number)
   * @param _price uint256 token price
   *
   * Requirements:
   * `tokenId` must exist
   * `owner` must the msg.owner
   */
  function setTokenPrice(uint256 _tokenId, uint256 _price) public {
    require(_exists(_tokenId), 'ERC721: Price set of nonexistent token');
    require(ownerOf(_tokenId) == _msgSender(), 'ERC721: Only owner of token can do this action');
    _tokenMeta[_tokenId].price = _price;
  }

  function tokenPrice(uint256 tokenId) public view virtual returns (uint256) {
    require(_exists(tokenId), 'ERC721: Price query for nonexistent token');
    return _tokenMeta[tokenId].price;
  }

  /**
   * @dev sets token meta
   * @param _tokenId uint256 token ID (token number)
   * @param _meta TokenMeta
   *
   * Requirements:
   * `tokenId` must exist
   * `owner` must the msg.owner
   */
  function _setTokenMeta(uint256 _tokenId, TokenMeta memory _meta) private {
    require(_exists(_tokenId));
    require(ownerOf(_tokenId) == _msgSender());
    _tokenMeta[_tokenId] = _meta;
  }

  function tokenMeta(uint256 _tokenId) public view returns (TokenMeta memory) {
    require(_exists(_tokenId));
    return _tokenMeta[_tokenId];
  }

  function artistOf(uint256 _tokenId) internal view virtual returns (address) {
    require(_exists(_tokenId));
    return _tokenMeta[_tokenId].artist;
  }

  /**
   * @dev purchase _tokenId
   * @param _tokenId uint256 token ID (token number)
   */
  function purchaseToken(uint256 _tokenId) public payable nonReentrant {
    require(
      msg.sender != address(0) && msg.sender != ownerOf(_tokenId),
      'ERC721: Curent sender is already owner of this token'
    );
    require(
      msg.value > _tokenMeta[_tokenId].price,
      'ERC721: insufficient balance to purchase the NFT'
    );
    // IERC20 token = IERC20(txFeeToken);
    // require(
    //   token.balanceOf(_msgSender()) > _tokenMeta[_tokenId].price,
    //   'ERC721: insufficient balance to purchase the NFT'
    // );
    require(_tokenMeta[_tokenId].sale == true, 'ERC721: This token is not for Sale currently');

    address tokenSeller = ownerOf(_tokenId);
    uint256 sellerProceeds = _tokenMeta[_tokenId].price;
    uint256 feesByTransfer = _payTxFee(_tokenId);
    // token.transferFrom(_msgSender(), tokenSeller, (sellerProceeds - feesByTransfer));
    payable(tokenSeller).transfer(sellerProceeds - feesByTransfer);
    _transfer(tokenSeller, msg.sender, _tokenId);
    _tokenMeta[_tokenId].sale = false;
  }

  function mint(
    address _owner,
    string memory _name,
    uint256 _price,
    uint256 _royalty,
    bool _sale
  ) public payable nonReentrant returns (uint256) {
    require(_price > 0);
    require(
      _royalty >= 0 && _royalty <= maxAllowedRoyalties,
      'ERC721: Very high royalty, you have to set a lower royalty'
    );
    uint256 feeCreateToken = _computeRoyalty(_price, feeCreateTokens);
    require(msg.value >= feeCreateToken, 'ERC721: insufficient amount to create NFT');

    // IERC20 token = IERC20(txFeeToken);
    // require(
    //   token.balanceOf(_msgSender()) > feeCreateTokens,
    //   'ERC721: insufficient balance to mint a new NFT'
    // );
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _safeMint(_owner, newItemId);

    TokenMeta memory meta = TokenMeta(newItemId, _price, _royalty, _name, _sale, _msgSender());
    _setTokenMeta(newItemId, meta);

    // token.transferFrom(_msgSender(), owner(), feeCreateTokens);
    payable(owner()).transfer(msg.value);

    return newItemId;
  }

  function mintCollectable(
    address _owner,
    string memory _name,
    uint256 _price,
    uint256 _royalty,
    bool _sale
  ) public onlyOwner returns (uint256) {
    require(msg.sender == owner(), 'artist only');
    require(_price > 0);
    require(
      _royalty >= 0 && _royalty <= maxAllowedRoyalties,
      'ERC721: Very high royalty, you have to set a lower royalty'
    );

    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(_owner, newItemId);

    TokenMeta memory meta = TokenMeta(newItemId, _price, _royalty, _name, _sale, _msgSender());
    _setTokenMeta(newItemId, meta);

    return newItemId;
  }

  function setExcluded(address excluded, bool status) external {
    require(msg.sender == owner(), 'artist only');
    excludedList[excluded] = status;
  }

  // function transferFrom(
  //   address from,
  //   address to,
  //   uint256 tokenId
  // ) public override {
  //   require(from == _msgSender(), 'ERC721: transfer from address called is not owner nor approved');
  //   require(
  //     _isApprovedOrOwner(_msgSender(), tokenId),
  //     'ERC721: transfer called is not owner nor approved'
  //   );
  //   if (excludedList[from] == false) {
  //     Marketis_payTxFee(tokenId);
  //   }
  //   _transfer(from, to, tokenId);
  // }

  // function safeTransferFrom(
  //   address from,
  //   address to,
  //   uint256 tokenId
  // ) public override {
  //   require(from == _msgSender(), 'ERC721: transfer from address called is not owner nor approved');
  //   require(
  //     _isApprovedOrOwner(_msgSender(), tokenId),
  //     'ERC721: transfer called is not owner nor approved'
  //   );
  //   if (excludedList[from] == false) {
  //     Marketis_payTxFee(tokenId);
  //   }
  //   safeTransferFrom(from, to, tokenId, '');
  // }

  // function safeTransferFrom(
  //   address from,
  //   address to,
  //   uint256 tokenId,
  //   bytes memory _data
  // ) public override {
  //   require(from == _msgSender(), 'ERC721: transfer from address called is not owner nor approved');
  //   require(
  //     _isApprovedOrOwner(_msgSender(), tokenId),
  //     'ERC721: transfer called is not owner nor approved'
  //   );
  //   if (excludedList[from] == false) {
  //     Marketis_payTxFee(tokenId);
  //   }
  //   _safeTransfer(from, to, tokenId, _data);
  // }

  function _payTxFee(uint256 _tokenId) internal returns (uint256) {
    // function _payTxFee(address from, uint256 _tokenId) internal returns (uint256) {
    // IERC20 token = IERC20(txFeeToken);
    uint256 feesByTransfer = 0;

    address tokenSeller = ownerOf(_tokenId);

    if (tokenSeller != owner()) {
      uint256 feeSellToken = _computeRoyalty(_tokenMeta[_tokenId].price, feeSellTokens);
      // require(
      //   token.balanceOf(from) > feeSellToken,
      //   'ERC721: insufficient balance to transfer the NFT'
      // );
      // require(
      //   token.balanceOf(from) > feeSellToken,
      //   'ERC721: insufficient balance to transfer the NFT'
      // );
      // token.transferFrom(from, owner(), feeSellToken);
      payable(owner()).transfer(feeSellToken);
      feesByTransfer += feeSellToken;
    }

    if (tokenSeller != owner() && tokenSeller != artistOf(_tokenId)) {
      uint256 royaltyFee = _computeRoyalty(
        _tokenMeta[_tokenId].price,
        _tokenMeta[_tokenId].royalty
      );
      // require(
      //   token.balanceOf(from) > royaltyFee,
      //   'ERC721: insufficient balance to transfer the NFT'
      // );
      // token.transferFrom(from, artistOf(_tokenId), royaltyFee);
      payable(artistOf(_tokenId)).transfer(royaltyFee);
      feesByTransfer += royaltyFee;
    }
    return feesByTransfer;
  }

  function _computeRoyalty(uint256 _price, uint256 txFeeAmount) internal pure returns (uint256) {
    return (_price * txFeeAmount) / 10000;
  }
}
