/** 
 *  Component providing implementation of CryptoRaw interface.
 *  A module providing actual implementation of CryptoRaw interafce in split-phase manner.
 *  @version   0.1
 * 	@date      2012-2013
 */
#include "ProtectLayerGlobals.h"
#include "aes.h" //AES constants
//#include "printf.h"

module CryptoRawP {

	//added AES
	uses interface AES;
	
	provides {
		interface Init;
		interface CryptoRaw;
	}
}
implementation {
	uint8_t 	m_state; 	/**< current state of the component - used to decice on next step inside task */
	PL_key_t* 	m_key1;		/**< handle to the key used as first (or only) one in cryptographic operations. Value is set before task is posted. */
	PL_key_t* 	m_key2;		/**< handle to the key used as second one in cryptographic operations (e.g., deriveKey). Value is set before task is posted. */
	uint8_t* 	m_buffer;	/**< buffer for subsequent encryption or decryption operation. Value is set before task is posted.  */
	uint8_t 	m_bufferTmp[10];	/**< temporary buffer for help with encryption or decryption operation. */
	uint8_t 	m_offset;   /**< offset inside buffer for subsequent encryption or decryption operation. Value is set before task is posted.  */
	uint8_t 	m_len;		/**< length of data inside buffer for subsequent encryption or decryption operation. Value is set before task is posted.  */
	uint16_t	m_dbgKeyID;	/**< unique key id for debugging */
	uint8_t         exp[240]; //expanded key
	//
	//	Init interface
	//
	command error_t Init.init() {
                PrintDbg("CryptoRawP", "Init.init() called.\n");
		// TODO: do other initialization
		m_state = 0;
		m_dbgKeyID = 0;
		return SUCCESS;
	}
	
	//
	//	CryptoRaw interface
	//	
	command error_t CryptoRaw.encryptBufferB(PL_key_t* key, uint8_t* counter, uint8_t* buffer, uint8_t offset, uint8_t* pLen) {
		
		PrintDbg("CryptoRawP", "KeyDistrib.encryptBufferB(offset = '%d' buffer = '%d', 1 = '%d', 6 = '%d'.\n", buffer[0],buffer[1],buffer[6]);
		
		PrintDbg("CryptoRawP", "KeyDistrib.encryptBufferB(buffer = '%d', 1 = '%d', 2 = '%d'.\n", buffer[0],buffer[1],buffer[2]);
		
		#ifdef AES
		
		
		uint8_t i;
		uint8_t j;
		uint8_t plainCounter[16];			
		uint8_t encCounter[16];
		
		//set rest of counter to zeros to fit AES block
		memset(plainCounter, 0, 16);	
		
		call AES.keyExpansion( exp, key->keyValue);
		
		//process buffer by blocks 
		for(i = 0; i < (pLen / BLOCK_SIZE); i++){
		
			plainCounter[0] = counter;
			call AES.encrypt( plainCounter, exp, encCounter);
			for (j := 0; i < BLOCK_SIZE; j++){
				buffer[offset + j] = buffer[offset + j] ^ encCounter[j];
			}
			counter++;
		}
		
		#else /* No AES, FAKE encryption*/
		uint8_t         i = 0;
	   // PrintDbg("CryptoRawP", "KeyDistrib.encryptBufferB(keyID = '%d', keyValue = '0x%x 0x%x') called.\n", key->dbgKeyID, key->keyValue[0], key->keyValue[1]);
		
		buffer += offset;
		// TODO: na define prepinani mezi AES vs. FAKE
		 
		// BUGBUG: no real encryption is performed, only transformation from DATA into form ENC|keyID|DATA (without |) is performed
		#define FAKEHEADERLEN 5
		// Backup first 5 bytes (needed for ENC|keyID)
		for (i = 0; i < FAKEHEADERLEN; i++) m_bufferTmp[i] = buffer[i];
		// Insert encryption header
		buffer[0] = 'E'; buffer[1] = 'N'; buffer[2] = 'C';
		buffer[3] = key->keyValue[0]; buffer[4] = key->keyValue[1];
		// Move data in buffer
		for (i = *pLen - 1; i >= FAKEHEADERLEN; i--) buffer[i + FAKEHEADERLEN] = buffer[i];
		// Insert data overwriten by fake header
		for (i = 0; i < FAKEHEADERLEN; i++) buffer[i+FAKEHEADERLEN] = m_bufferTmp[i];

		// Increase length of encrypted data by header
		*pLen = *pLen + FAKEHEADERLEN;
		
		#endif /* AES */
		
		
		return SUCCESS;
	}
	
	
	command error_t CryptoRaw.decryptBufferB(PL_key_t* key, uint8_t* counter, uint8_t* buffer, uint8_t offset, uint8_t* pLen) {
		
		error_t status = SUCCESS;
		
		PrintDbg("CryptoRawP", "KeyDistrib.decryptBufferB(keyID = '%d', keyValue = '0x%x 0x%x') called.\n", key->dbgKeyID, key->keyValue[0], key->keyValue[1]);
		#ifdef AES
		
		uint8_t i;
		uint8_t j;
		uint8_t plainCounter[16];			
		uint8_t encCounter[16];
		
		//set rest of counter to zeros to fit AES block
		memset(plainCounter, 0, 16);	
		
		call AES.keyExpansion( exp, key->keyValue);
		
		//process buffer by blocks 
		for(i = 0; i < (pLen / BLOCK_SIZE); i++){
		
			plainCounter[0] = counter;
			call AES.decrypt( plainCounter, exp, encCounter);
			for (j := 0; i < BLOCK_SIZE; j++){
				buffer[offset + j] = buffer[offset + j] ^ encCounter[j];
			}
			counter++;
		}
		
		#else /* No AES, FAKE encryption*/
		uint8_t i = 0;

		

		buffer += offset;

		// TODO: na define prepinani mezi AES vs. FAKE

		// BUGBUG: no real decryption is performed, only transformation from ENC|keyID|DATA into DATA and check for expected key value
		#define FAKEHEADERLEN 5

		// Check ENC tag
		if (buffer[0] == 'E' && buffer[1] == 'N' && buffer[2] == 'C') {
			if ((buffer[3] == key->keyValue[0]) && (buffer[4] == key->keyValue[1])) {
				// Remove encryption header
				for (i = FAKEHEADERLEN; i < *pLen; i++) buffer[i - FAKEHEADERLEN] = buffer[i];

				// Decrease length of decrypted data by fake header
				*pLen -= FAKEHEADERLEN;
			}
			else {
				PrintDbg("CryptoRawP", "Different key used for encryption \n");
				status = EDIFFERENTKEY;
			}

		}
		else {
			PrintDbg("CryptoRawP", "ENC tag not detected.\n");
			status = EINVALIDDECRYPTION;
		}

		//m_len = Decrypt(m_key1, m_buffer + m_offset, m_len);
		
		#endif /* AES */
		
		return status;
	}
	
	
	
	command error_t CryptoRaw.deriveKey(PL_key_t* masterKey, uint8_t* derivationData, uint8_t offset, uint8_t len, PL_key_t* derivedKey) {
        PrintDbg("CryptoRawP", "KeyDistrib.task_deriveKey(masterKey = '%d') called.\n", m_key1->dbgKeyID);
		
		//TODO: predelat na blocking verzi
		
		// TODO: Mod derivace s vyuzitim AESem
		// derivedKey = E_masterKey(derivationData)
		
		#ifdef AES
		
		call AES.keyExpansion( exp, masterKey->keyValue);
		call AES.encrypt( derivationData + offset, exp, derivedKey->keyValue);		
		
		return SUCCESS;
		
		#else /* No AES, use previous split-phase version */
		if (m_state & FLAG_STATE_CRYPTO_DERIV) {
			return EALREADY;	
		}
		else {
			// Change state to enecryption and post task to encrypt
			m_state |= FLAG_STATE_CRYPTO_DERIV;
			m_key1 = masterKey; 
			m_key2 = derivedKey; 
			m_buffer = derivationData; m_offset = offset; m_len = len;
						
			post task_deriveKey();
			
			return SUCCESS;
		}
		
		
		memcpy(m_key2->keyValue, m_buffer + m_offset, KEY_LENGTH);
		// we are done
		m_key2->dbgKeyID = m_dbgKeyID++;	// assign debug key id
		#endif /* AES */
		PrintDbg("CryptoRawP", "\t derivedKey = '%d')\n", m_key2->dbgKeyID);
			m_state &= ~FLAG_STATE_CRYPTO_DERIV;
		
	}
	
	command error_t generateKeyB(PL_key_t* newKey) {
	
		//TODO pokud potřeba
		return SUCCESS;
	}
	
	
	
	
	
	
	
	
	
	
/*
*	DEPRICATED
*
*/	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	//
	//	CryptoRaw interface
	//
	task void task_encryptBuffer() {
                error_t status = call CryptoRaw.encryptBufferB(m_key1, m_buffer, m_offset, &m_len);

/*
                uint8_t         i = 0;
                PrintDbg("CryptoRawP", "KeyDistrib.task_encryptBuffer(keyID = '%d', keyValue = '0x%x 0x%x') called.\n", m_key1->dbgKeyID, m_key1->keyValue[0], m_key1->keyValue[1]);

                // BUGBUG: no real encryption is performed, only transformation from DATA into form ENC|keyID|DATA (without |) is performed
                #define FAKEHEADERLEN 5
                // Backup first 5 bytes (needed for ENC|keyID)
                for (i = 0; i < FAKEHEADERLEN; i++) m_bufferTmp[i] = m_buffer[i];
                // Insert encryption header
                m_buffer[0] = 'E'; m_buffer[1] = 'N'; m_buffer[2] = 'C';
                m_buffer[3] = m_key1->keyValue[0]; m_buffer[4] = m_key1->keyValue[1];
                // Move data in buffer
                for (i = m_len; i >= FAKEHEADERLEN; i--) m_buffer[i + FAKEHEADERLEN] = m_buffer[i];
                // Insert data overwriten by fake header
                for (i = 0; i < FAKEHEADERLEN; i++) m_buffer[i+FAKEHEADERLEN] = m_bufferTmp[i];

                // Increase length of encrypted data by header
                m_len += FAKEHEADERLEN;

		//m_len = Encrypt(m_key1, m_buffer + m_offset, m_len);
*/

		// we are done
                signal CryptoRaw.encryptBufferDone(status, m_buffer, m_len);
		// Cleanup
 		m_buffer = NULL;
		m_state &= ~FLAG_STATE_CRYPTO_ENCRYPTION;
	}
	command error_t CryptoRaw.encryptBuffer(PL_key_t* key, uint8_t* buffer, uint8_t offset, uint8_t len) {
                PrintDbg("CryptoRawP", "KeyDistrib.encryptBuffer(keyID = '%d') called.\n", key->dbgKeyID);
		if (m_state & FLAG_STATE_CRYPTO_ENCRYPTION) {
			return EALREADY;	
		}
		else {
			// Change state to encryption and post task to encrypt
			m_state |= FLAG_STATE_CRYPTO_ENCRYPTION;
			m_key1 = key; m_buffer = buffer; m_offset = offset; m_len = len;
			post task_encryptBuffer();
			return SUCCESS;
		}
	}	
        //default event void CryptoRaw.encryptBufferDone(error_t status, uint8_t* buffer, uint8_t resultLen) {}

	task void task_decryptBuffer() {
               error_t status = call CryptoRaw.decryptBufferB(m_key1, m_buffer, m_offset, &m_len);
/*
                uint8_t i = 0;


                PrintDbg("CryptoRawP", "KeyDistrib.task_decryptBuffer(keyID = '%d', keyValue = '0x%x') called.\n", m_key1->dbgKeyID, m_key1->keyValue);

                // BUGBUG: no real decryption is performed, only transformation from ENC|keyID|DATA into DATA and check for expected key value
                #define FAKEHEADERLEN 5

                // Check ENC tag
                if (m_buffer[0] == 'E' && m_buffer[1] == 'N' && m_buffer[2] == 'C') {
                    if ((m_buffer[3] == m_key1->keyValue[0]) && (m_buffer[4] == m_key1->keyValue[1])) {
                        // Remove encryption header
                        for (i = FAKEHEADERLEN; i < m_len; i++) m_buffer[i - FAKEHEADERLEN] = m_buffer[i];

                        // Decrease length of decrypted data by fake header
                        m_len -= FAKEHEADERLEN;
                    }
                    else {
                        PrintDbg("CryptoRawP", "Different key used for encryption \n");
                        status = EDIFFERENTKEY;
                    }

                }
                else {
                    PrintDbg("CryptoRawP", "ENC tag not detected.\n");
                    status = EINVALIDDECRYPTION;
                }

		//m_len = Decrypt(m_key1, m_buffer + m_offset, m_len);
*/
		// we are done
                signal CryptoRaw.decryptBufferDone(status, m_buffer, m_len);
		// Cleanup
 		m_buffer = NULL;
		m_state &= ~FLAG_STATE_CRYPTO_DECRYPTION;
	}
	
	command error_t CryptoRaw.decryptBuffer(PL_key_t* key, uint8_t* buffer, uint8_t offset, uint8_t len) {
                PrintDbg("CryptoRawP", "KeyDistrib.decryptBuffer(keyID = '%d') called.\n", key->dbgKeyID);
		if (m_state & FLAG_STATE_CRYPTO_DECRYPTION) {
			return EALREADY;	
		}
		else {
			// Change state to decryption and post task to decrypt
			m_state |= FLAG_STATE_CRYPTO_DECRYPTION;
			m_key1 = key; m_buffer = buffer; m_offset = offset; m_len = len;
			post task_decryptBuffer();
			return SUCCESS;
		}
	}
	//default event void CryptoRaw.decryptBufferDone(error_t status, uint8_t* buffer, uint8_t resultLen) {}


	task void task_deriveKey() {
                PrintDbg("CryptoRawP", "KeyDistrib.task_deriveKey(masterKey = '%d') called.\n", m_key1->dbgKeyID);
                //m_len = Encrypt(m_key1, m_buffer + m_offset, m_len);
                memcpy(m_key2->keyValue, m_buffer + m_offset, KEY_LENGTH);
		// we are done
		m_key2->dbgKeyID = m_dbgKeyID++;	// assign debug key id
                PrintDbg("CryptoRawP", "\t derivedKey = '%d')\n", m_key2->dbgKeyID);
		m_state &= ~FLAG_STATE_CRYPTO_DERIV;
		signal CryptoRaw.deriveKeyDone(SUCCESS, m_key2);
	}
	
	command error_t CryptoRaw.deriveKey(PL_key_t* masterKey, uint8_t* derivationData, uint8_t offset, uint8_t len, PL_key_t* derivedKey) {
                PrintDbg("CryptoRawP", "KeyDistrib.task_deriveKey(masterKey = '%d') called.\n", m_key1->dbgKeyID);
		if (m_state & FLAG_STATE_CRYPTO_DERIV) {
			return EALREADY;	
		}
		else {
			// Change state to enecryption and post task to encrypt
			m_state |= FLAG_STATE_CRYPTO_DERIV;
			m_key1 = masterKey; 
			m_key2 = derivedKey; 
			m_buffer = derivationData; m_offset = offset; m_len = len;
			post task_deriveKey();
			return SUCCESS;
		}
	}

	//default event void CryptoRaw.deriveKeyDone(error_t status, PL_key_t* derivedKey) {}

	task void task_generateKey() {
                PrintDbg("CryptoRawP", "KeyDistrib.task_generateKey() called.\n");
		// RNG(m_key1->keyValue, KEY_LENGTH);
		// we are done
		m_key1->dbgKeyID = m_dbgKeyID++;	// assign debug key id
                dbg("CryptoRawP", "\t newKey = '%d')\n", m_key1->dbgKeyID);
		m_state &= ~FLAG_STATE_CRYPTO_GENERATE;
		signal CryptoRaw.generateKeyDone(SUCCESS, m_key1);
	}
	
	command error_t CryptoRaw.generateKey(PL_key_t* newKey) {
                PrintDbg("CryptoRawP", "KeyDistrib.generateKey().\n");
		if (m_state & FLAG_STATE_CRYPTO_GENERATE) {
			return EALREADY;	
		}
		else {
			// Change state to generation and post task to generate
			m_state |= FLAG_STATE_CRYPTO_GENERATE;
			m_key1 = newKey; 
			post task_generateKey();
			return SUCCESS;
		}
	}

	//default event void CryptoRaw.generateKeyDone(error_t status, PL_key_t* newKey) {}

        command error_t CryptoRaw.generateKeyBlocking(PL_key_t* newKey) {
                PrintDbg("CryptoRawP", "KeyDistrib.generateKeyBlocking().\n");
                newKey->keyType = KEY_TONODE;
                newKey->dbgKeyID = m_dbgKeyID++;	// assign debug key id
                // TODO: RNG(newKey->keyValue, KEY_LENGTH);
                PrintDbg("CryptoRawP", "\t newKey = '%d')\n", newKey->dbgKeyID);
                return SUCCESS;
        }

}
