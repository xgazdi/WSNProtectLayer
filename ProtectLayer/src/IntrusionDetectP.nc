/**
 * Module IntrusionDetectP implements interfaces provided by configuration IntrusionDetectC.
 * 	@version   0.1
 * 	@date      2012-2013
 */
 
#include "ProtectLayerGlobals.h"
#include "printf.h"

module IntrusionDetectP {
	uses {
		interface AMSend;
		interface Receive;
		interface Receive as ReceiveMsgCopy;
		interface SharedData;
		interface Timer<TMilli> as TimerIDS;
		interface BlockWrite;
	}
	provides {
		interface Init;
		interface IntrusionDetect;
	}
}

implementation {
	message_t m_msg;
	
	// Logging
	message_t* m_logMsg;
	message_t* m_lastLogMsg;
	message_t m_memLogMsg;
	bool m_storageBusy = FALSE;

	bool m_radioBusy = FALSE;
	combinedData_t * combinedData;
	NODE_REPUTATION reputation;
	SavedData_t * savedData;
	IDS_STATUS ids_status = IDS_RESET;
	uint32_t offset_write = 0;
	
	
	//
	//	Init interface
	//
	command error_t Init.init() {
		// TODO: do other initialization
		// TODO: how will we collect the data from SharedData
                dbg("IDSState", "IDS initialization called.\n");
		combinedData = call SharedData.getAllData();
		//call TimerIDS.startPeriodic(1024);
		
		m_logMsg = &m_memLogMsg;
		
		return SUCCESS;
	}
	
	command NODE_REPUTATION IntrusionDetect.getNodeReputation(uint8_t nodeid) {
		//savedData = call SharedData.getNodeState(nodeid);
		//reputation = (*savedData).idsData.neighbor_reputation;
		reputation =  (*call SharedData.getNodeState(nodeid)).idsData.neighbor_reputation;
                dbg("IDSState", "Reputation of node %d is: %d.\n", nodeid, reputation);
		return reputation;
	}
	
	command void IntrusionDetect.switchIDSoff(){
		// TODO implementation
		ids_status = IDS_OFF;
	}

	command void IntrusionDetect.switchIDSon(){
		// TODO implementation
		ids_status = IDS_ON;
	}
	
	command void IntrusionDetect.resetIDS(){
		// TODO implementation
		ids_status = IDS_RESET;
	}
	
	// TODO: IDS component will send messages using tasks and will check the error code, if fail, the same task will be generated again.
	
	event void AMSend.sendDone(message_t* msg, error_t status){
		if (msg==&m_msg) {
			m_radioBusy = FALSE;
		}
	}

	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len){
		
		if (len == sizeof(IDSMsg_t)) {
			
			
			IDSMsg_t* idsmsg = (IDSMsg_t*) payload;
                        dbg("IDSState", "Packet received. Receiver: %d. Broadcast address: %d. Reputation: %d\n", idsmsg->receiver, AM_BROADCAST_ADDR, idsmsg->reputation);
			
			/* is the message for me? */
			// TODO: finalize this part!!
			if (TOS_NODE_ID == idsmsg->receiver || idsmsg->receiver == AM_BROADCAST_ADDR) {
			
				/* somebody requested to know reputation of one of my neighbor */
				if (idsmsg->reputation == 0) {
                                        dbg("IDSState", "Node %d wants to know reputation of node %d.\n", idsmsg->sender, idsmsg->nodeID);
					// TODO: reaction - send the reputation! Split-phase: will be done in a task.
				}
				
				/* somebody sent me reputation of one of its neighbor */
				else {
                                        dbg("IDSState", "Node %d says: the reputation of node %d is %d.\n", idsmsg-> sender, idsmsg->nodeID, idsmsg->reputation);
					// TODO: reaction - store the reputation or combine it with its own collected reputation!
				}
			
			}
			
		}

		return msg;
	}
	
	task void task_sendMessage() {
	  	error_t rval=SUCCESS;
		
		rval = call AMSend.send(AM_BROADCAST_ADDR, &m_msg, sizeof(IDSMsg_t));
	    if (rval == SUCCESS) {
	        m_radioBusy = TRUE;
                        dbg("IDSState", "IDS: IntrusionDetectP.task_sendMessage send returned %d.\n",rval);
	        return;
	    }
		return;
	}

	// Testing purposes
	event void TimerIDS.fired(){
		error_t rval;

                dbg("IDSState", "IDS timer fired. My time: %d.\n", call TimerIDS.getNow());
		
		
	    if (!m_radioBusy) {
		      IDSMsg_t* idsmsg = (IDSMsg_t*)(call AMSend.getPayload(&m_msg, sizeof(IDSMsg_t)));
		      if (idsmsg == NULL) {
				return;
		      }
		      
		      idsmsg->sender = TOS_NODE_ID;
		      idsmsg->receiver = AM_BROADCAST_ADDR;
		      idsmsg->nodeID = 7; // send me reputation of node 7.
		      idsmsg->reputation = 0; // I am asking for reputation.
		      dbg("IDSState", "The receiver will be: %d\n", idsmsg->receiver);
		      // send message
		      rval = call AMSend.send(AM_BROADCAST_ADDR, &m_msg, sizeof(IDSMsg_t));
			  if (rval == SUCCESS) {
			      m_radioBusy = TRUE;
			    }
			}
	}


	// Messages passed to the IDS from privacy component
	event message_t * ReceiveMsgCopy.receive(message_t *msg, void *payload, uint8_t len){
                PrintDbg("IDS", "ReceiveMsgCopy.receive\n");
                //is storage busy?
		if (m_storageBusy)
		{
			// storage busy, packet cannot be logged
			return msg; 	
		}
		else
		{
                        //PrintDbg("IntrusionDetectP", "Going to write\n");
                        //log packet
			m_lastLogMsg = msg;
			if (call BlockWrite.write(offset_write, payload, LOGGED_SIZE) == SUCCESS)
			{
				m_storageBusy = TRUE;
				offset_write += LOGGED_SIZE;
				return m_logMsg;
			}
			else
			{
				//logging failed, return original msg
				return msg;
			}
		}

		

	}

	event void BlockWrite.eraseDone(error_t error){
	}

	event void BlockWrite.writeDone(storage_addr_t addr, void *buf, storage_len_t len, error_t error){
		// TODO: chech whether payload == buf
            //PrintDbg("IntrusionDetectP", "BlockWrite.writeDone executed with %d\n", error);
            if (error == SUCCESS) PrintDbg("IntrusionDetectP", "writeDone success\n");
            else PrintDbg("IntrusionDetectP", "writeDone fail with %d \n", error);

            m_logMsg = m_lastLogMsg;
            m_storageBusy = FALSE;

	}

	event void BlockWrite.syncDone(error_t error){
	}
}
