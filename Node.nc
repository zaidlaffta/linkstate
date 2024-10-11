/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/socket.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
    uses interface Boot;
    uses interface SplitControl as AMControl;
    uses interface Receive;
    uses interface SimpleSend as Sender;
	uses interface SimpleSend as Flooder;
	
	uses interface NeighborDiscovery;
	uses interface LinkStateRouting;
   uses interface CommandHandler;
  
   
   uses interface Timer<TMilli> as RoutingTimer;
}
implementation{
   pack sendPackage;
	buffer_t globalBuffer[MAX_NUM_OF_SOCKETS]; //Global buffer variable(one buffer per connection)
	
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void initGlobalBuffers();
	//uint8_t fillBuffer(uint16_t* buff, uint8_t size, uint16_t start);
	uint8_t fillBuffer(uint16_t *buff, uint8_t pos, uint8_t size, uint16_t nextVal);
   void readBuffer(uint16_t *buff, uint8_t loc, uint8_t size);
   void printGlobalBuffer(socket_t fd);
	uint16_t min(uint16_t a, uint16_t b);
   
   event void Boot.booted(){
      call AMControl.start();
		initGlobalBuffers();
      dbg(GENERAL_CHANNEL, "Booted\n");
   }
   
   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
      call NeighborDiscovery.run();
      call RoutingTimer.startPeriodic(1024*8);
	  (GENERAL_CHANNEL, "LinkState routing started");
   }

   event void AMControl.stopDone(error_t err){}
   
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         tcp_pack* myTCPRecv = (tcp_pack*) myMsg->payload;
         tcp_pack  myTCPSend;
         uint8_t nextHop;
         
         if(myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_TCP) {	
		      if(myMsg->dest == AM_BROADCAST_ADDR) {	
		      	dbg(GENERAL_CHANNEL, "Package recieved\n");
		      	dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
		      	call Flooder.send(*myMsg, myMsg->dest);
		      }
		      else if(myMsg->dest != TOS_NODE_ID) {
		      	nextHop = call LinkStateRouting.getNextHopTo(myMsg->dest);
		      	dbg(ROUTING_CHANNEL, "Package received for %d. Forwarding to next hop: %d\n", myMsg->dest, nextHop);
		      	call Sender.send(*myMsg, nextHop);
		      }
		      else {
		      	if(myMsg->protocol == PROTOCOL_PING){
		      		dbg(GENERAL_CHANNEL, "Package recieved\n");
	         		dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
		      	}
		      
		      }
		   }
         
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

	event void RoutingTimer.fired() {
		call LinkStateRouting.run();
		dbg(GENERAL_CHANNEL, "Calling LinkState routing");
	}



	event void NeighborDiscovery.changed(uint8_t id) { }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
   	uint8_t nextHop = call LinkStateRouting.getNextHopTo(destination);
      dbg(GENERAL_CHANNEL, "PING EVENT\n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, nextHop);
      //call Flooder.send(sendPackage, destination); //To show packet flooding
   }

   event void CommandHandler.printNeighbors(){
   	call NeighborDiscovery.print();
   }

   event void CommandHandler.printRouteTable(){
   	call LinkStateRouting.print();
   }

   event void CommandHandler.printLinkState(){
   	call LinkStateRouting.print();
   }
   event void CommandHandler.printDistanceVector() {}

   event void CommandHandler.setTestServer() {}

   event void CommandHandler.setTestClient() {}

   event void CommandHandler.setAppServer() {}

   event void CommandHandler.setAppClient() {}
  

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

	//Pass the head of the buffer to this function
	void readBuffer(uint16_t *buff, uint8_t loc, uint8_t size) {
		uint8_t i;
		
		for(i = 0; i < size; i++) {
			printf("%hu, ", buff[(loc + i) % SOCKET_BUFFER_SIZE]);
		}
		
	}
	
	uint8_t fillBuffer(uint16_t *buff, uint8_t pos, uint8_t size, uint16_t nextVal) {
		uint8_t count;
		
		for(count = 0; count < size; count++) {
			buff[(pos + count) % SOCKET_BUFFER_SIZE] = nextVal++;
		}
		
		return count;
		
	}

	void printGlobalBuffer(socket_t fd) {
		uint8_t i;
   	buffer_t buffer = globalBuffer[fd];
   	printf("\nSocket %d global buffer:\n", fd);
   	for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
   		printf("%4d ", buffer.buff[i]);
   	}
   	printf("\ncurrentPosition(%d), lastWritten(%d), lastRead(%d), transferSize(%d)\n", 
   		buffer.currentPosition, 
   		buffer.lastWritten, 
   		buffer.lastRead,
   		buffer.transferSize
   	);
	}

	uint16_t min(uint16_t a, uint16_t b) {
		return (a < b) ? a : b;
	}
	
	void initGlobalBuffers() {
		uint8_t i, j;
		for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
			globalBuffer[i].currentPosition = 0;
			globalBuffer[i].lastWritten = 0;
			globalBuffer[i].lastRead = 0;
			globalBuffer[i].transferSize = 0;
			globalBuffer[i].sendSize = 0;
			globalBuffer[i].firstWrite = TRUE;
			globalBuffer[i].nextVal = 1;
			for(j = 0; j < SOCKET_BUFFER_SIZE; j++) {
				globalBuffer[i].buff[j] = 0;
			}
		}
	}
	

	
	
	
	
}
