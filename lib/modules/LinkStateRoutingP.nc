#include <../../includes/entry.h>

module LinkStateRoutingP {
    provides interface LinkStateRouting;
    uses interface NeighborDiscovery;
    uses interface SimpleSend as LSPFlooder;
    uses interface Receive as Receiver;
    uses interface List<LSP> as LinkStateInfo;
    uses interface List<RouteEntry> as Confirmed;
    uses interface List<RouteEntry> as Tentative;
    uses interface Hashmap<RouteEntry> as RoutingTable;
    uses interface Timer<TMilli> as RoutingTimer;
}

implementation {
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
    void floodLSP();
    error_t addLSP(LSP);
    bool isUpdatedLSP(LSP);
    void updateLSP(LSP);
    bool isInLinkStateInfo(LSP);
    uint8_t getPos(uint8_t);
    void printLinkStateInfo();

    // Command to start the Link State Routing process
    command void LinkStateRouting.run() {
        floodLSP();
        call RoutingTimer.startOneShot(1024*8);  // Start the timer for periodic flooding
    }

    // Command to print the Link State Information
    command void printLinkStateInfo() {
        uint8_t size = call LinkStateInfo.size();
        for (uint8_t i = 0; i < size; i++) {
            LSP lsp = call LinkStateInfo.get(i);
            dbg(GENERAL_CHANNEL, "\tNode %d neighbors: [ ", lsp.id);
            for (uint8_t j = 0; j < lsp.numNeighbors; j++) {
                dbg(GENERAL_CHANNEL, "%d ", lsp.neighbors[j]);
            }
            dbg(GENERAL_CHANNEL, "]\n");
        }
    }

    // Command to print the entire routing information
    command void LinkStateRouting.print() {
        call printLinkStateInfo();
        call printRoutingTable();
    }

    // Event triggered when the routing timer fires, which invokes Dijkstra's algorithm
    event void RoutingTimer.fired() {
        call dijkstraForwardSearch();
        call updateAges();  // Updates the age of entries in LinkStateInfo
    }

    // Event to handle state changes from NeighborDiscovery
    event void NeighborDiscovery.changed(uint8_t id) {
        floodLSP();  // Floods the LSP packet whenever a neighbor changes
    }

    // Event triggered upon receiving a packet; handles LSP packets to update routing state
    event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) { 
        if(len == sizeof(pack)) {
            pack* myMsg = (pack*) payload;
            LSP lsp = *(LSP*) myMsg->payload;
            if(myMsg->protocol == PROTOCOL_LINKSTATE) {
                if(isInLinkStateInfo(lsp)) {
                    if(isUpdatedLSP(lsp)) updateLSP(lsp);  // Update existing LSP if it’s newer
                } else addLSP(lsp);  // Add new LSP to LinkStateInfo
            }
        }
        return msg;
    }

    // Function to flood LSP packet to all neighbors
    void floodLSP() {
        LSP myLSP;
        pack myPack;
        uint8_t numNeighbors = call NeighborDiscovery.getNumNeighbors(); 
        uint8_t *neighbors = call NeighborDiscovery.getNeighbors();

        myLSP.id = TOS_NODE_ID;
        myLSP.numNeighbors = numNeighbors;
        memcpy(myLSP.neighbors, neighbors, numNeighbors);  // Copy neighbors into LSP struct
        myLSP.age = 5;  // Set age for the LSP

        makePack(&myPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_LINKSTATE, 0, (uint8_t*)&myLSP, sizeof(LSP));
        call LSPFlooder.send(myPack, myPack.dest);  // Send the LSP packet
    }

    // Helper function to create a packet structure
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);  // Copy payload into the packet
    }

    // Command to add a new LSP entry to LinkStateInfo list
    error_t addLSP(LSP lsp) {
        if (call LinkStateInfo.size() < MAX_LSP_ENTRIES) {
            return call LinkStateInfo.pushBack(lsp);
        }
        return FAIL;  // Return failure if list is full
    }

    // Function to check if the incoming LSP is more updated than the stored one
    bool isUpdatedLSP(LSP lsp) {
        for (uint8_t i = 0; i < call LinkStateInfo.size(); i++) {
            LSP existingLSP = call LinkStateInfo.get(i);
            if (existingLSP.id == lsp.id && lsp.age > existingLSP.age) {
                return TRUE;
            }
        }
        return FALSE;
    }

    // Function to update an existing LSP entry in the LinkStateInfo list
    void updateLSP(LSP lsp) {
        for (uint8_t i = 0; i < call LinkStateInfo.size(); i++) {
            LSP* existingLSP = &call LinkStateInfo.get(i);
            if (existingLSP->id == lsp.id) {
                *existingLSP = lsp;  // Update the existing LSP with the new one
            }
        }
    }

    // Function to check if an LSP entry already exists in LinkStateInfo
    bool isInLinkStateInfo(LSP lsp) {
        for (uint8_t i = 0; i < call LinkStateInfo.size(); i++) {
            if (call LinkStateInfo.get(i).id == lsp.id) {
                return TRUE;
            }
        }
        return FALSE;
    }
}