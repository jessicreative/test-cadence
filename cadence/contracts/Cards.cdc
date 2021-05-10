import NonFungibleToken from "./NonFungibleToken.cdc"

//Cards
//NFT items for users
//
pub contract Cards: NonFungibleToken {
    
    //Events
    //
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    pub event Minted(id: UInt64, typeID: UInt64)

    // Named Paths
    //
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let MinterStoragePath: StoragePath

    // totalSupply
    // The total number of cards that have been minted
    //will be used as ID for now
    pub var totalSupply: UInt64

    // NFT
    //
    pub resource NFT: NonFungibleToken.INFT {
        // The token's ID
        pub let id: UInt64
        // The token's type, e.g. 3 == Hat
        pub let typeID: UInt64

        // initializer
        //
        init(initID: UInt64, initTypeID: UInt64) {
            self.id = initID
            self.typeID = initTypeID
        }
    }

    // This is the interface that users can cast their Cards Collection as
    // to allow others to deposit Cards into their Collection. It also allows for reading
    // the details of Cards in the Collection.
    pub resource interface CardsCollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT, metadata: {String : String})
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowCard(id: UInt64): &Cards.NFT? {
            // If the result isn't nil, the id of the returned reference
            // should be the same as the argument to the function
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow Card reference: The ID of the returned reference is incorrect"
            }
        }
        pub fun getMetadata(id: UInt64) : {String : String}
    }

  pub resource Collection: CardsCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        //
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}
        pub var metadataObjs: {UInt64: { String : String }}

        // withdraw
        // Removes an NFT from the collection and moves it to the caller
        //
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID)?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        // deposit
        // Takes a NFT and adds it to the collections dictionary
        // and adds the ID to the id array
        //
        pub fun deposit(token: @NonFungibleToken.NFT, metadata: {String : String}) {
            let token <- token as! @Cards.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            self.metadataObjs[id] = metadata

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // getIDs
        // Returns an array of the IDs that are in the collection
        //
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT
        // Gets a reference to an NFT in the collection
        // so that the caller can read its metadata and call its methods
        //
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        // borrowKittyItem
        // Gets a reference to an NFT in the collection as a KittyItem,
        // exposing all of its fields (including the typeID).
        // This is safe as there are no functions that can be called on the KittyItem.
        //
        pub fun borrowCard(id: UInt64): &Cards.NFT? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &Cards.NFT
            } else {
                return nil
            }
        }

        pub fun updateMetadata(id: UInt64, metadata: {String: String})
        {
            self.metadataObjs[id] = metadata
        }

        pub fun getMetadata(id: UInt64): {String : String} {
            return self.metadataObjs[id]!
        }

        //destructor
        destroy() {
            destroy self.ownedNFTs
        }

        //initializer
        //
        init () {
            self.ownedNFTs <- {}
            self.metadataObjs = {}
        }
    }

    // createEmptyCollection
    // public function that anyone can call to create a new empty collection
    //
    pub fun createEmptyCollection(): @Collection {
        return <- create Collection()
    }

    //PINATA VERSION
    pub resource NFTMinter {
        //exchanged the idCount to be totalSupply as ID, consistent with Kitty-Items

        //adjusted argument of mintNFT to include recipient: &{NonFungibleToken.CollectionPublic}, typeID: UInt64, otherwise create Cards.NFT will have less argument and no reference to typeID
        pub fun mintNFT(typeID: UInt64): @NFT {
            emit Minted(id: Cards.totalSupply, typeID: typeID)
            var newNFT <- create Cards.NFT(initID: Cards.totalSupply, initTypeID: typeID)
            Cards.totalSupply = Cards.totalSupply + (1 as UInt64)
            return <-newNFT
        }
    }
    //KITTY-ITEMS VERSION
    // NFTMinter
    // Resource that an admin or something similar would own to be
    // able to mint new NFTs
    //
    // pub resource NFTMinter {

        // mintNFT
        // Mints a new NFT with a new ID
		// and deposit it in the recipients collection using their collection reference
        //
        //     pub fun mintNFT(recipient: &{NonFungibleToken.CollectionPublic}, typeID: UInt64) {
        //         emit Minted(id: Cards.totalSupply, typeID: typeID)
        //         // deposit it in the recipient's account using their reference
        // 		recipient.deposit(token: <-create Cards.NFT(initID: Cards.totalSupply, initTypeID: typeID))

        //         Cards.totalSupply = Cards.totalSupply + (1 as UInt64)
        //     }
        // }
        //
    // }

    // fetch
    // Get a reference to a KittyItem from an account's Collection, if available.
    // If an account does not have a Cards.Collection, panic.
    // If it has a collection but does not contain the itemID, return nil.
    // If it has a collection and that collection contains the itemID, return a reference to that.
    //
    pub fun fetch(_ from: Address, itemID: UInt64): &Cards.NFT? {
        let collection = getAccount(from)
            .getCapability(Cards.CollectionPublicPath)
            .borrow<&Cards.Collection{Cards.CardsCollectionPublic}>()
            ?? panic("Couldn't get collection")
        // We trust Cards.Collection.borowCard to get the correct itemID
        // (it checks it before returning it).
        return collection.borrowCard(id: itemID)
    }

    // initializer
    //
    init() {
        // Set our named paths
        self.CollectionStoragePath = /storage/cardsCollection
        self.CollectionPublicPath = /public/cardsCollection
        self.MinterStoragePath = /storage/cardsMinter

        // Initialize the total supply
        self.totalSupply = 0

        //ADAPTED FROM PINATA
        //
        //changed from self.account.save(<-self.createEmptyCollection(), to: /storage/NFTCollection) to:
        self.account.save(<-self.createEmptyCollection(), to: self.CollectionStoragePath)

        //changed this from Pinata's self.account.link<&{NFTReceiver}>(/public/NFTReceiver, target: /storage/NFTCollection) to:
        self.account.link<&{CardsCollectionPublic}>(self.CollectionPublicPath, target: self.CollectionStoragePath)

        //instead of this from Pinata: self.account.save(<-create NFTMinter(), to: /storage/NFTMinter)
        //from kitty-items
        // Create a Minter resource and save it to storage
        let minter <- create NFTMinter()
        self.account.save(<-minter, to: self.MinterStoragePath)

        emit ContractInitialized()

        //self.account.save(<-self.createEmptyCollection(), to: /storage/NFTCollection)
        //self.account.link<&{NFTReceiver}>(/public/NFTReceiver, target: /storage/NFTCollection)
	}
}