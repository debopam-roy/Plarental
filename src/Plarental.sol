// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Plarental is Ownable, ReentrancyGuard {

    struct Tree {
        string s_no;
        string name;
        uint256 price;
        uint quantity;
    }

    struct Sapling {
        string name;
        uint256 price;
        uint quantity;
        uint256 plantedAt;
    }

    struct Reward {
        uint256 fruits;
        uint256 flowers;
        uint256 woods;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    error Plarental_UNAUTHORIZED();
    error Plarental_INVALID_ADDRESS();
    error Plarental_TREE_NOT_FOUND(string name);
    error Plarental_TREE_UNAVAILABLE(string name, uint requested, uint available);
    error Plarental_NOT_ENOUGH_MONEY(uint sent, uint required);

    mapping (string => Tree) private trees;
    mapping (address => Sapling[]) private saplings_owned;
    mapping (address => mapping(string => Reward)) private rewards;

    event EtherReceived(address indexed sender, uint amount);
    event TreeAdded(string indexed name, string s_no, uint256 price, uint quantity);
    event TreeRemoved(string indexed name);
    event TreePriceUpdated(string indexed name, uint256 newPrice);
    event TreeTransferred(address indexed from, address indexed to, string name, uint quantity);
    event TreeReturned(address indexed from, string name, uint quantity);
    event RewardsClaimed(address indexed owner, string treeName, Reward reward);

    uint256 constant REWARD_INTERVAL = 30 days;

    modifier validPlantation(string memory _name, uint _quantity) {
        Tree storage tree = trees[_name];
        if (bytes(tree.s_no).length == 0) {
            revert Plarental_TREE_NOT_FOUND(_name);
        }
        if(tree.quantity < _quantity){
            revert Plarental_TREE_UNAVAILABLE(_name, _quantity, tree.quantity);
        }
        if(tree.price * _quantity > msg.value){
            revert Plarental_NOT_ENOUGH_MONEY(msg.value, tree.price * _quantity);
        }
        _;
    }

    /******************************************************Core Tree Functions *******************************************************/

    function addTree(string memory name, string memory s_no, uint256 price, uint quantity) external onlyOwner {
        Tree storage tree = trees[name];
        if (bytes(tree.s_no).length == 0) {
            trees[name] = Tree({
                s_no: s_no,
                name: name,
                price: price,
                quantity: quantity
            });
            emit TreeAdded(name, s_no, price, quantity);
        } else {
            tree.quantity += quantity;
        }
    }

    function removeTree(string memory name) external onlyOwner {
        if (bytes(trees[name].s_no).length == 0) {
            revert Plarental_TREE_NOT_FOUND(name);
        }
        delete trees[name];
        emit TreeRemoved(name);
    }

    function updateTreePrice(string memory name, uint256 new_price) external onlyOwner {
        Tree storage tree = trees[name];
        if (bytes(tree.s_no).length == 0) {
            revert Plarental_TREE_NOT_FOUND(name);
        }
        tree.price = new_price;
        emit TreePriceUpdated(name, new_price);
    }

    function showTree(string memory _name) public view returns (Tree memory) {
        return trees[_name];
    }

    /*********************************************************************************************************************************/

    function plantTrees(string memory _name, uint _quantity) external payable validPlantation(_name, _quantity) nonReentrant {
        Tree storage tree = trees[_name];
        tree.quantity -= _quantity;

        saplings_owned[msg.sender].push(Sapling({
            name: _name,
            price: tree.price * _quantity,
            quantity: _quantity,
            plantedAt: block.timestamp
        }));
    }

    function showOwnedTrees(address _owner) public view returns (Sapling[] memory) {
        return saplings_owned[_owner];
    }

    function transferOwnership(address to, string memory tree_name, uint quantity) external {
        if(to == address(0)) {
            revert Plarental_INVALID_ADDRESS();
        }
        Sapling[] storage ownedTrees = saplings_owned[msg.sender];

        for (uint i = 0; i < ownedTrees.length; i++) {
            if (keccak256(bytes(ownedTrees[i].name)) == keccak256(bytes(tree_name)) && ownedTrees[i].quantity >= quantity) {
                ownedTrees[i].quantity -= quantity;
                if (ownedTrees[i].quantity == 0) {
                    delete ownedTrees[i];
                }
                saplings_owned[to].push(Sapling({
                    name: tree_name,
                    price: ownedTrees[i].price / ownedTrees[i].quantity * quantity,
                    quantity: quantity,
                    plantedAt: ownedTrees[i].plantedAt
                }));
                emit TreeTransferred(msg.sender, to, tree_name, quantity);
                return;
            }
        }
        revert Plarental_TREE_NOT_FOUND(tree_name);
    }

    function calculateRewards(address owner, string memory treeName) private view returns (Reward memory) {
        Sapling[] storage ownedTrees = saplings_owned[owner];
        for (uint i = 0; i < ownedTrees.length; i++) {
            if (keccak256(bytes(ownedTrees[i].name)) == keccak256(bytes(treeName))) {
                uint256 elapsedTime = block.timestamp - ownedTrees[i].plantedAt;
                uint256 intervals = elapsedTime / REWARD_INTERVAL;
                return Reward({
                    fruits: intervals * 10, // Example reward calculation
                    flowers: intervals * 5,  // Example reward calculation
                    woods: intervals * 2     // Example reward calculation
                });
            }
        }
        revert Plarental_TREE_NOT_FOUND(treeName);
    }

    function claimRewards(string memory treeName) public nonReentrant {
        Reward memory reward = calculateRewards(msg.sender, treeName);
        rewards[msg.sender][treeName] = reward;
        emit RewardsClaimed(msg.sender, treeName, reward);
    }

    function returnTrees(string memory tree_name, uint quantity) external nonReentrant{
        
        Sapling[] storage ownedTrees = saplings_owned[msg.sender];

        for (uint i = 0; i < ownedTrees.length; i++) {
            if (keccak256(bytes(ownedTrees[i].name)) == keccak256(bytes(tree_name)) && ownedTrees[i].quantity >= quantity) {
                ownedTrees[i].quantity -= quantity;
                if (ownedTrees[i].quantity == 0) {
                    delete ownedTrees[i];
                }
                if (ownedTrees[i].price * ownedTrees[i].quantity>address(this).balance){
                    revert Plarental_NOT_ENOUGH_MONEY(address(this).balance, ownedTrees[i].price * ownedTrees[i].quantity);
                }
                (bool success, ) = payable(msg.sender).call{value:ownedTrees[i].price * ownedTrees[i].quantity}("");
                if (success){
                trees[tree_name].quantity+= quantity;
                emit TreeReturned(msg.sender, tree_name, quantity);
                return;
                }
            }
        }
        
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        revert Plarental_UNAUTHORIZED();
    }
}
