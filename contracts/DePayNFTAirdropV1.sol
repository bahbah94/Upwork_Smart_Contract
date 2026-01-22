// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DePayNFTAirdropV1 is Ownable, ReentrancyGuard {

    // Storage for all airdrops to identify executed airdrops
    mapping (
      // receiver address
      address => mapping (
        // token address
        address => mapping (
          // token id
          uint256 => bool
        )
      )
    ) public airdrops;

    // Storage for all airdrops that have been canceled
    mapping (
      // distributor address
      address => mapping (
        // token address
        address => bool
      )
    ) public cancledAirdrops; // ? This should be canceledAirdrops?

    // Being able to pause the aidrop contract (just in case)
    bool public paused;

    // EIP712
    // * HERE is not clear what the domain mentioned here is and where its used, & why is it hardcoded?
    // ! actually in Domain for EIP723, usually you woud have a domain name, version, chainId, verifying Contract
    // ! without these replay attacks could be done on different chains/contracts
    string private constant domain = "EIP712Domain(string name)";
    bytes32 public constant domainTypeHash = keccak256(abi.encodePacked(domain));
    string private constant airdropType = "Airdrop(address tokenAddress,address[] receivers,bool isERC1155,uint256[] tokenIds)";
    bytes32 public constant airdropTypeHash = keccak256(abi.encodePacked(airdropType));
    bytes32 private domainSeparator;

    //
    struct Airdrop {
      //
      // The address of the token contract
      //
      address tokenAddress;
      //
      // Addresses of users which are allowed to withdrawal an airdrop
      //
      address[] receivers;
      //
      // Indicates the NFT standard if standard supports ERC1155 or not
      //
      bool isERC1155;
      //
      // TokenIds
      //
      uint256[] tokenIds;
    }
    
    //
    modifier onlyUnpaused {
      require(paused == false, "Airdrops are paused!");
      _;
    }
    // ! you probably would want an event like Event Paused(bool) or something like this

    ////////////////////////////////////////////////
    //////// C O N S T R U C T O R
    //
    // Initalizes the EIP712 domain separator.
    // ! problem is no chain binding
    constructor() public {
      domainSeparator = keccak256(abi.encode(
        domainTypeHash,
        keccak256("DePayNFTAirdropV1")
      ));
    }

    ////////////////////////////////////////////////
    //////// F U N C T I O N S
    //
    // Claim an aidroped NFT
    //
    function claim(
      address tokenAddress,
      address[] memory receivers,
      bool isERC1155,
      uint256[] memory tokenIds,
      uint256 index,
      uint8 v,
      bytes32 r,
      bytes32 s
    ) onlyUnpaused nonReentrant external {
      address distributor = ecrecover(
        hashAirdrop(
          tokenAddress,
          receivers,
          isERC1155,
          tokenIds
        ),
        v,
        r,
        s
      );
      // ! Here its dangrous i think to use index for both tokenIds and receivers. 
      // ! firstly, the mapping for tokenIds is not clear, also len(tokeniDs) != len(receivers)
      // ! Also no checks for when index > length of each tokenIds or receivers. Potentially add the following
      // ! require(index < receivers.length, "Index out of receivers bounds");
      // ! require(index < tokenIds.length, "Index out of tokenIds bounds");
      // ! require(receivers.length == tokenIds.length, "Receivers and tokenIds length mismatch");

      uint256 tokenId = tokenIds[index];
      address receiver = receivers[index];

      // ! perhaps here we could do require(receiver != address(0)) to prevent zero address
      // ! also the signaure used seems to cover the entire array, not that this particular receiver is entitled to a token( DESIGN FLAW!!!!)

      require(receiver == msg.sender, "Defined airdrop receiver needs to be msg.sender!");

      require(airdrops[receiver][tokenAddress][tokenId] == false, "Receiver has already retrieved this airdrop!");
      // ! This state change should probably happen after the token transfers otherwise we will have state inconsistencies
      airdrops[receiver][tokenAddress][tokenId] = true;
      
      // ! this is fine since we checking if any changes to cancellation has happened
      require(cancledAirdrops[distributor][tokenAddress] == false, "Distributor has canceled this airdrop!");

      // ! below i think we should check ownership for something they dont really own. I have added for both 1155 and 721
      if(isERC1155) { // ERC1155
        IERC1155 token = IERC1155(tokenAddress);
        // ! require(
        // !  token.balanceOf(distributor, tokenId) >= 1,
        // !  "Distributor does not own token"
      // !);
        token.safeTransferFrom(distributor, receiver, tokenId, 1, bytes(""));
      } else { // ERC721
        // !require(
        //  ! token.ownerOf(tokenId) == distributor,
        //  ! "Distributor is not owner of token"
        // !);
        IERC721 token = IERC721(tokenAddress);
        token.safeTransferFrom(distributor, receiver, tokenId);
      }
    }

    
    //
    // Internal, private method to hash an airdrop
    //
    function hashAirdrop(address tokenAddress, address[] memory receivers, bool isERC1155, uint256[] memory tokenIds) private view returns (bytes32){
      return keccak256(abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        keccak256(abi.encode(
          airdropTypeHash,
          keccak256(abi.encodePacked(tokenAddress)), // ! For each of this use abi.encode, as encodePacked can lead to hash collisions
          keccak256(abi.encodePacked(receivers)), // ! Same thing for receivers, isERC1155 and tokenIds encoding too.
          keccak256(abi.encodePacked(isERC1155)),
          keccak256(abi.encodePacked(tokenIds))
        ))
      ));
    }

    //
    // Change set paused to
    // ! should probably have the event 

    function setPausedTo(bool value) external onlyOwner {
      paused = value;
      // ! emit event Paused(True) --> something like this
    }

    //
    // Cancel airdrop
    // ! technically distributor can cancel after some users claimed
    // ! Also this is not per airdrop but rather per tokenAddress, so if distributor signs Airdrop A (token X) & Airdrop B (token Y) --> both are cancelled
    function cancel(address tokenAddress) external {
      cancledAirdrops[msg.sender][tokenAddress] = true;
    }

    //
    // Kill contract
    // ! This is most dangerous function
    // ! Owner can destroy and block all pending claims, introduces centralization risk
    function kill() external onlyOwner {
      // ! possible remove self destruct or add it after, maybe make a function that checks all airdrops are claimed like AllAirdropsClaimed
      // ! require(AllAirdropsClaimed(), "Cannot kill with pending airdrops");
      selfdestruct(msg.sender);
    }
}
