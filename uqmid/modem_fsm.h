#ifndef __UQMID_MODEM_FSM_H
#define __UQMID_MODEM_FSM_H

enum modem_fsm_state {
	MODEM_ST_IDLE,
	MODEM_ST_RESYNC,
	MODEM_ST_GET_VERSION,
	MODEM_ST_GET_MODEL,
	MODEM_ST_GET_IMSI,
	MODEM_ST_POWEROFF,
	MODEM_ST_UNLOCK_PIN,
	MODEM_ST_CONFIGURE_MODEM,
	MODEM_ST_POWERON,
	MODEM_ST_NETSEARCH,
	MODEM_ST_REGISTERED,
	MODEM_ST_START_IFACE,
	MODEM_ST_LIVE,
	MODEM_ST_FAILED,
	MODEM_ST_DESTROY,
};

enum modem_fsm_event {
	MODEM_EV_REQ_START,
	MODEM_EV_REQ_CONFIGURED,

	MODEM_EV_RX_SYNC,
	MODEM_EV_RX_VERSION,

	MODEM_EV_RX_MODEL,
	MODEM_EV_RX_MANUFACTURER,
	MODEM_EV_RX_REVISION,

	MODEM_EV_RX_IMSI,
	MODEM_EV_RX_UIM_FAILED,
	MODEM_EV_RX_UIM_GET_SLOT_FAILED,
	MODEM_EV_RX_UIM_VALID_ICCID,
	MODEM_EV_RX_UIM_NO_UIM_FOUND,
	MODEM_EV_RX_IMSI_DMS_FAILED,

	MODEM_EV_RX_POWEROFF,
	MODEM_EV_RX_POWERON,
	MODEM_EV_RX_POWERSET,

	MODEM_EV_RX_UNLOCKED_PIN,
	MODEM_EV_RX_UIM_PUK_REQUIRED,
	MODEM_EV_RX_UIM_PIN_REQUIRED,
	MODEM_EV_RX_UIM_READY,

	MODEM_EV_RX_GET_PROFILE_LIST,
	MODEM_EV_RX_MODIFIED_PROFILE,
	MODEM_EV_RX_CONFIGURED,

	MODEM_EV_RX_GET_SERVING_SYSTEM,
	MODEM_EV_RX_REGISTERED,
	MODEM_EV_RX_UNREGISTERED,
	MODEM_EV_RX_SEARCHING,

	MODEM_EV_RX_SUBSCRIBED,
	MODEM_EV_RX_SUBSCRIBE_FAILED,

	MODEM_EV_RX_FAILED,
	MODEM_EV_RX_SUCCEED, /* a generic callback succeeded */
	MODEM_EV_REQ_DESTROY,
};


struct modem;
void modem_fsm_start(struct modem *modem);
struct osmo_fsm_inst *modem_fsm_alloc(struct modem *modem);

#endif /* __UQMID_MODEM_FSM_H */
