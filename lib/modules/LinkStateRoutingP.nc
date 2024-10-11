#include <../../includes/entry.h>

module LinkStateRoutingP {
	// Provides this to offer link state routing 
	provides interface LinkStateRouting;
	
	// Uses this to get neighbor information
	uses interface NeighborDiscovery;
	// Uses this to flood LSPs
	uses interface SimpleSend as LSPFlooder;
	// Uses this to receive LSP packets
	uses interface Receive as Receiver;
	// Uses this to store the LSPs received, also acts as an adjacency list
	uses interface List<LSP> as LinkStateInfo;
	// Used for Dijkstra's Forward Learning algorithm
	uses {
		interface List<RouteEntry> as Confirmed;
		interface List<RouteEntry> as Tentative;
	}
	// Uses this to store the routing table
	uses interface Hashmap<RouteEntry> as RoutingTable;
	uses interface Timer<TMilli> as RoutingTimer;
}
implementation {
	// List helper function prototypes
	void floodLSP();
	error_t addLSP(LSP);
	void swapLSP(uint8_t, uint8_t);
	bool isUpdatedLSP(LSP);
	void updateLSP(LSP);
	bool isInLinkStateInfo(LSP);
	uint8_t getPos(uint8_t);
	void sortLinkStateInfo();		// Insertion sort
	void printLinkStateInfo();
	uint8_t getPos(uint8_t id);
	bool inConfirmed(uint8_t);
	bool inTentative(uint8_t);
	uint8_t minInTentative();
	void clearConfirmed();
	void dijkstraForwardSearch();
	void updateRoutingTable();
	void printRoutingTable();
	void updateAges();

	command void LinkStateRouting.run() {
		floodLSP();
		call RoutingTimer.startOneShot(1024 * 8);
	}

	command void LinkStateRouting.print() {
		// Print out all of the link state advertisements used to compute the routing table
		printLinkStateInfo();
		// Print out the routing table
		printRoutingTable();
	}

	command uint8_t LinkStateRouting.getNextHopTo(uint8_t dest) {
		RouteEntry entry = call RoutingTable.get(dest);
		return entry.next_hop; 
	}

	event void RoutingTimer.fired() {
		dijkstraForwardSearch();
		updateAges();
	}

	event void NeighborDiscovery.changed(uint8_t id) {
		// Neighbor state has changed
		floodLSP();
	}

	event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) { 
		if (len == sizeof(pack)) {
			pack* myMsg = (pack*) payload;
			LSP* receivedLSP = (LSP*) myMsg->payload;
			LSP lsp = *receivedLSP;

			// Populate LinkStateInfo list using the LSPs received
			if (myMsg->protocol == PROTOCOL_LINKSTATE) {
				// If LSP received is already in LinkStateInfo
				if (isInLinkStateInfo(lsp)) {
					// Check if LSP received is different than one in LinkStateInfo
					if (isUpdatedLSP(lsp))  // If so, then update it
						updateLSP(lsp);
					else return msg;
				} else addLSP(lsp);  // If not, then add it to LinkStateInfo
				
				// Keep this list sorted
				sortLinkStateInfo();
			}
			return msg;
		}
		dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
		return msg;
	}

	// Generates a LSP, encapsulates it into a pack, and floods it on the network
	void floodLSP() {
		LSP myLSP;
		pack myPack;

		// Get a list of current neighbors
		uint8_t i, numNeighbors = call NeighborDiscovery.getNumNeighbors(); 
		uint8_t *neighbors = call NeighborDiscovery.getNeighbors();

		// Encapsulate this list into a LSP
		myLSP.numNeighbors = numNeighbors;
		myLSP.id = TOS_NODE_ID;
		for (i = 0; i < numNeighbors; i++) {
			myLSP.neighbors[i] = neighbors[i];
		}
		myLSP.age = 5;

		// Encapsulate this LSP into a pack struct
		makePack(&myPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_LINKSTATE, 0, &myLSP, PACKET_MAX_PAYLOAD_SIZE);
		// Flood this pack on the network
		call LSPFlooder.send(myPack, myPack.dest);
	}

	// Prints contents of LinkStateInfo
	void printLinkStateInfo() {
		uint8_t size = call LinkStateInfo.size();
		uint8_t i, j;
		LSP lsp;
		
		dbg(GENERAL_CHANNEL, "Node %d Link State Info (%d entries):\n", TOS_NODE_ID, size);
		
		for (i = 0; i < size; i++) {
			lsp = call LinkStateInfo.get(i);
			dbg(GENERAL_CHANNEL, "\tNode %d neighbors: [ ", lsp.id);
			for (j = 0; j < lsp.numNeighbors; j++) {
				dbg(GENERAL_CHANNEL, "%d ", lsp.neighbors[j]);
			}
			dbg(GENERAL_CHANNEL, "]\n");
		}
	}

	// Prints the contents of RoutingTable
	void printRoutingTable() {
		uint8_t i, size = call RoutingTable.size();
		RouteEntry entry;
		uint32_t *keys = call RoutingTable.getKeys();
		
		dbg(GENERAL_CHANNEL, "\nRouting Table for node %d:\n", TOS_NODE_ID);
		
		for (i = 0; i < size; i++) {
			entry = call RoutingTable.get(keys[i]);
			dbg(GENERAL_CHANNEL, "\tDestination: %d, Cost: %d, Next Hop: %d\n", entry.dest, entry.cost, entry.next_hop);
		}
	}
	
	// Decrements the age field of all LSP entries in LinkStateInfo and removes if age reaches 0
	void updateAges() {
		uint8_t i, size = call LinkStateInfo.size();
		LSP lsp;

		for (i = 0; i < size; i++) {
			lsp = call LinkStateInfo.get(i);
			if (lsp.age <= 1 || lsp.age > 5) {
				call LinkStateInfo.remove(i);
			} else {
				lsp.age--;
				call LinkStateInfo.replace(i, lsp);
			}
		}
	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
}
