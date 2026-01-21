// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


contract BlockchainMonsters {

    // Interface definitions (implemented from scratch without OpenZeppelin)

    // IERC165 interface
    interface IERC165 {
        function supportsInterface(bytes4 interfaceId) external view returns (bool);
    }

    // IERC721 interface
    interface IERC721 is IERC165 {
        event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
        event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
        event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

        function balanceOf(address owner) external view returns (uint256 balance);
        function ownerOf(uint256 tokenId) external view returns (address owner);
        function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
        function safeTransferFrom(address from, address to, uint256 tokenId) external;
        function transferFrom(address from, address to, uint256 tokenId) external;
        function approve(address to, uint256 tokenId) external;
        function setApprovalForAll(address operator, bool approved) external;
        function getApproved(uint256 tokenId) external view returns (address operator);
        function isApprovedForAll(address owner, address operator) external view returns (bool);
    }

    // IERC721Metadata interface
    interface IERC721Metadata {
        function name() external view returns (string memory);
        function symbol() external view returns (string memory);
        function tokenURI(uint256 tokenId) external view returns (string memory);
    }

    // IERC721Enumerable interface (for listing tokens)
    interface IERC721Enumerable {
        function totalSupply() external view returns (uint256);
        function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
        function tokenByIndex(uint256 index) external view returns (uint256);
    }

    // Contract variables

    string private _name = "BlockchainMonsters";
    string private _symbol = "BMON";
    uint256 private _totalSupply = 0;
    uint256 private _nextTokenId = 1; // Start token IDs from 1

    // Mappings for ERC721 functionality
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Enumerable mappings
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens; // owner => index => tokenId
    mapping(uint256 => uint256) private _ownedTokensIndex; // tokenId => index in owner's list
    uint256[] private _allTokens; // List of all tokenIds
    mapping(uint256 => uint256) private _allTokensIndex; // tokenId => index in allTokens

    // Monster-specific data
    struct Monster {
        uint256 health;    // Base health points (1-100)
        uint256 attack;    // Base attack power (1-50)
        uint256 defense;   // Base defense (1-50)
        uint256 speed;     // Speed for turn order (1-30)
        uint256 level;     // Starts at 1, increases with wins
        uint256 experience; // XP to level up
        uint256 generation; // 0 for originals, increases with breeding
        uint256 parent1;   // Token ID of first parent (0 if original)
        uint256 parent2;   // Token ID of second parent (0 if original)
        string element;    // Fire, Water, Earth, Air (affects battles)
    }

    mapping(uint256 => Monster) private _monsters;

    // Marketplace listings: tokenId => price (in wei)
    mapping(uint256 => uint256) private _listings;

    // Events for monster actions
    event MonsterMinted(uint256 indexed tokenId, address indexed owner);
    event MonsterBred(uint256 indexed newTokenId, uint256 parent1, uint256 parent2);
    event BattleStarted(uint256 indexed monster1, uint256 indexed monster2);
    event BattleWon(uint256 indexed winner, uint256 indexed loser);
    event MonsterListed(uint256 indexed tokenId, uint256 price);
    event MonsterSold(uint256 indexed tokenId, address indexed buyer, uint256 price);

    // Modifiers
    modifier onlyOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        _;
    }

    modifier exists(uint256 tokenId) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        _;
    }

    modifier notListed(uint256 tokenId) {
        require(_listings[tokenId] == 0, "Token is listed for sale");
        _;
    }

    // Constructor
    constructor() {
        // Nothing needed, but we can mint some initial monsters if desired
    }

    // ERC165 support
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC721).interfaceId ||
               interfaceId == type(IERC721Metadata).interfaceId ||
               interfaceId == type(IERC721Enumerable).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }

    // ERC721 functions

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view exists(tokenId) returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "Cannot approve to self");
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "Not authorized");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view exists(tokenId) returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        require(operator != msg.sender, "Cannot approve self");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _safeTransfer(from, to, tokenId, data);
    }

    // Internal transfer helper
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Non-ERC721 receiver");
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Not owner");
        require(to != address(0), "Zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals
        _tokenApprovals[tokenId] = address(0);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    // ERC721 receiver check
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private returns (bool) {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("Non-ERC721 receiver");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    // IERC721Receiver interface (for safe transfers)
    interface IERC721Receiver {
        function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
    }

    // Metadata functions
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view exists(tokenId) returns (string memory) {
        // Simple base URI + tokenId (in production, use IPFS or something)
        return string(abi.encodePacked("https://example.com/metadata/", _toString(tokenId), ".json"));
    }

    // Enumerable functions
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        require(index < balanceOf(owner), "Index out of bounds");
        return _ownedTokens[owner][index];
    }

    function tokenByIndex(uint256 index) public view returns (uint256) {
        require(index < totalSupply(), "Index out of bounds");
        return _allTokens[index];
    }

    // Internal enumerable helpers
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = _balances[to];
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = _balances[from] - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }

    // Hooks for transfer (from OpenZeppelin style)
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {
        if (from == address(0)) {
            _totalSupply += 1;
            _addTokenToAllTokensEnumeration(tokenId);
        }

        if (to != from) {
            if (to != address(0)) {
                _addTokenToOwnerEnumeration(to, tokenId);
            }
            if (from != address(0)) {
                _removeTokenFromOwnerEnumeration(from, tokenId);
            }
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    // Monster game functions

    // Mint a new monster (costs ETH for fun, say 0.01 ETH)
    function mintMonster() public payable {
        require(msg.value >= 0.01 ether, "Minting fee required");

        uint256 tokenId = _nextTokenId++;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        _addTokenToOwnerEnumeration(msg.sender, tokenId);
        _addTokenToAllTokensEnumeration(tokenId);

        // Generate random attributes using pseudo-RNG
        uint256 rand = _pseudoRandom();
        _monsters[tokenId] = Monster({
            health: (rand % 100) + 1,
            attack: (rand % 50) + 1,
            defense: (rand % 50) + 1,
            speed: (rand % 30) + 1,
            level: 1,
            experience: 0,
            generation: 0,
            parent1: 0,
            parent2: 0,
            element: _randomElement(rand)
        });

        emit Transfer(address(0), msg.sender, tokenId);
        emit MonsterMinted(tokenId, msg.sender);
    }

    // Breed two monsters (must own both, new monster inherits averages)
    function breed(uint256 parent1, uint256 parent2) public onlyOwner(parent1) onlyOwner(parent2) notListed(parent1) notListed(parent2) {
        require(parent1 != parent2, "Cannot breed same monster");

        uint256 newTokenId = _nextTokenId++;
        _owners[newTokenId] = msg.sender;
        _balances[msg.sender] += 1;
        _addTokenToOwnerEnumeration(msg.sender, newTokenId);
        _addTokenToAllTokensEnumeration(newTokenId);

        Monster memory p1 = _monsters[parent1];
        Monster memory p2 = _monsters[parent2];

        uint256 rand = _pseudoRandom();
        _monsters[newTokenId] = Monster({
            health: (p1.health + p2.health) / 2 + (rand % 10) - 5, // Slight mutation
            attack: (p1.attack + p2.attack) / 2 + (rand % 10) - 5,
            defense: (p1.defense + p2.defense) / 2 + (rand % 10) - 5,
            speed: (p1.speed + p2.speed) / 2 + (rand % 10) - 5,
            level: 1,
            experience: 0,
            generation: max(p1.generation, p2.generation) + 1,
            parent1: parent1,
            parent2: parent2,
            element: (rand % 2 == 0) ? p1.element : p2.element
        });

        // Clamp values
        _clampAttributes(newTokenId);

        emit Transfer(address(0), msg.sender, newTokenId);
        emit MonsterBred(newTokenId, parent1, parent2);
    }

    // Battle two monsters (anyone can initiate if they own one, other must approve?)
    // For simplicity, owner of monster1 challenges monster2 (which can be anyone's)
    // No approval needed, as it's non-destructive
    function battle(uint256 monster1, uint256 monster2) public onlyOwner(monster1) exists(monster2) notListed(monster1) notListed(monster2) {
        require(monster1 != monster2, "Cannot battle self");

        emit BattleStarted(monster1, monster2);

        Monster memory m1 = _monsters[monster1];
        Monster memory m2 = _monsters[monster2];

        // Adjust for levels
        m1.health += m1.level * 10;
        m1.attack += m1.level * 5;
        m1.defense += m1.level * 5;
        m2.health += m2.level * 10;
        m2.attack += m2.level * 5;
        m2.defense += m2.level * 5;

        // Element advantages (simple rock-paper-scissors)
        int256 advantage1 = _elementAdvantage(m1.element, m2.element);
        int256 advantage2 = _elementAdvantage(m2.element, m1.element);

        m1.attack = uint256(int256(m1.attack) + advantage1 * 10);
        m2.attack = uint256(int256(m2.attack) + advantage2 * 10);

        // Simple battle loop: Alternate attacks until one health <=0
        bool turn1 = m1.speed >= m2.speed; // Faster goes first
        uint256 h1 = m1.health;
        uint256 h2 = m2.health;

        while (h1 > 0 && h2 > 0) {
            if (turn1) {
                uint256 damage = m1.attack > m2.defense ? m1.attack - m2.defense : 1;
                h2 = h2 > damage ? h2 - damage : 0;
            } else {
                uint256 damage = m2.attack > m1.defense ? m2.attack - m1.defense : 1;
                h1 = h1 > damage ? h1 - damage : 0;
            }
            turn1 = !turn1;
        }

        uint256 winner = h1 > 0 ? monster1 : monster2;
        uint256 loser = h1 > 0 ? monster2 : monster1;

        // Award XP to winner
        _monsters[winner].experience += 100;
        if (_monsters[winner].experience >= 100 * _monsters[winner].level) {
            _monsters[winner].level += 1;
            _monsters[winner].experience = 0;
        }

        emit BattleWon(winner, loser);
    }

    // Marketplace functions

    // List a monster for sale
    function listForSale(uint256 tokenId, uint256 price) public onlyOwner(tokenId) {
        require(price > 0, "Price must be positive");
        _listings[tokenId] = price;
        emit MonsterListed(tokenId, price);
    }

    // Delist
    function delist(uint256 tokenId) public onlyOwner(tokenId) {
        _listings[tokenId] = 0;
    }

    // Buy a listed monster
    function buyMonster(uint256 tokenId) public payable exists(tokenId) {
        uint256 price = _listings[tokenId];
        require(price > 0, "Not for sale");
        require(msg.value >= price, "Insufficient payment");

        address seller = ownerOf(tokenId);
        _listings[tokenId] = 0;

        // Transfer token
        _transfer(seller, msg.sender, tokenId);

        // Pay seller
        payable(seller).transfer(price);

        // Refund excess
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }

        emit MonsterSold(tokenId, msg.sender, price);
    }

    // View monster details
    function getMonster(uint256 tokenId) public view exists(tokenId) returns (Monster memory) {
        return _monsters[tokenId];
    }

    // View listing price
    function getListingPrice(uint256 tokenId) public view returns (uint256) {
        return _listings[tokenId];
    }

    // Helper functions

    function _pseudoRandom() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, _nextTokenId)));
    }

    function _randomElement(uint256 rand) private pure returns (string memory) {
        uint256 mod = rand % 4;
        if (mod == 0) return "Fire";
        if (mod == 1) return "Water";
        if (mod == 2) return "Earth";
        return "Air";
    }

    function _clampAttributes(uint256 tokenId) private {
        Monster storage m = _monsters[tokenId];
        m.health = m.health < 1 ? 1 : (m.health > 100 ? 100 : m.health);
        m.attack = m.attack < 1 ? 1 : (m.attack > 50 ? 50 : m.attack);
        m.defense = m.defense < 1 ? 1 : (m.defense > 50 ? 50 : m.defense);
        m.speed = m.speed < 1 ? 1 : (m.speed > 30 ? 30 : m.speed);
    }

    function _elementAdvantage(string memory e1, string memory e2) private pure returns (int256) {
        bytes32 h1 = keccak256(abi.encodePacked(e1));
        bytes32 h2 = keccak256(abi.encodePacked(e2));
        if (h1 == keccak256("Fire") && h2 == keccak256("Earth")) return 1;
        if (h1 == keccak256("Water") && h2 == keccak256("Fire")) return 1;
        if (h1 == keccak256("Earth") && h2 == keccak256("Air")) return 1;
        if (h1 == keccak256("Air") && h2 == keccak256("Water")) return 1;
        if (h1 == h2) return 0;
        return -1; // Disadvantage
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    // Utility to convert uint to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Fallback to receive ETH
    receive() external payable {}
}
