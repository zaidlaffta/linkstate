interface LinkStateRouting {
	command void run();
	command void print();
	command uint8_t getNextHopTo(uint8_t);
	command void printLinkStateInfo();
    command void printRoutingTable();
}
