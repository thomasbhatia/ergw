%% Copyright 2015, Travelping GmbH <info@travelping.com>

%% This program is free software; you can redistribute it and/or
%% modify it under the terms of the GNU General Public License
%% as published by the Free Software Foundation; either version
%% 2 of the License, or (at your option) any later version.

-module(gtp_v2_c).

-behaviour(gtp_protocol).

%% API
-export([gtp_msg_type/1,
	 build_response/1,
	 build_echo_request/0,
	 type/0, port/0]).

%% support functions
-export([handle_sgsn/3, build_recovery/2]).

-include_lib("gtplib/include/gtp_packet.hrl").
-include("include/ergw.hrl").

%%====================================================================
%% API
%%====================================================================
handle_sgsn(IEs, Context, State) ->
    RecoveryCount =
	case lists:keyfind(v2_recovery, 1, IEs) of
	    #v2_recovery{restart_counter = RCnt} ->
		RCnt;
	    _ ->
		undefined
	end,
    gtp_context:handle_recovery(RecoveryCount, Context, State).

build_recovery(#gtp_port{restart_counter = RCnt}, true) ->
    [#v2_recovery{restart_counter = RCnt}];
build_recovery(_, _) ->
    [].

type() -> 'gtp-c'.
port() -> ?GTP2c_PORT.

build_echo_request() ->
    #gtp{version = v2, type = echo_request, tei = 0, ie = []}.

build_response({Type, TEI, IEs}) ->
    #gtp{version = v2, type = gtp_msg_response(Type), tei = TEI, ie = map_reply_ies(IEs)};
build_response({Type, IEs}) ->
    #gtp{version = v2, type = gtp_msg_response(Type), tei = 0, ie = map_reply_ies(IEs)}.

gtp_msg_type(echo_request)					-> request;
gtp_msg_type(echo_response)					-> response;
gtp_msg_type(version_not_supported)				-> other;
gtp_msg_type(create_session_request)				-> request;
gtp_msg_type(create_session_response)				-> response;
gtp_msg_type(delete_session_request)				-> request;
gtp_msg_type(delete_session_response)				-> response;
gtp_msg_type(modify_bearer_request)				-> request;
gtp_msg_type(modify_bearer_response)				-> response;
gtp_msg_type(change_notification_request)			-> request;
gtp_msg_type(change_notification_response)			-> response;
gtp_msg_type(modify_bearer_command)				-> other;
gtp_msg_type(modify_bearer_failure_indication)			-> other;
gtp_msg_type(delete_bearer_command)				-> other;
gtp_msg_type(delete_bearer_failure_indication)			-> other;
gtp_msg_type(bearer_resource_command)				-> other;
gtp_msg_type(bearer_resource_failure_indication)		-> other;
gtp_msg_type(downlink_data_notification_failure_indication)	-> other;
gtp_msg_type(trace_session_activation)				-> other;
gtp_msg_type(trace_session_deactivation)			-> other;
gtp_msg_type(stop_paging_indication)				-> other;
gtp_msg_type(create_bearer_request)				-> request;
gtp_msg_type(create_bearer_response)				-> response;
gtp_msg_type(update_bearer_request)				-> request;
gtp_msg_type(update_bearer_response)				-> response;
gtp_msg_type(delete_bearer_request)				-> request;
gtp_msg_type(delete_bearer_response)				-> response;
gtp_msg_type(delete_pdn_connection_set_request)			-> request;
gtp_msg_type(delete_pdn_connection_set_response)		-> response;
gtp_msg_type(pgw_downlink_triggering_notification)		-> other;
gtp_msg_type(pgw_downlink_triggering_acknowledge)		-> other;
gtp_msg_type(identification_request)				-> request;
gtp_msg_type(identification_response)				-> response;
gtp_msg_type(context_request)					-> request;
gtp_msg_type(context_response)					-> response;
gtp_msg_type(context_acknowledge)				-> other;
gtp_msg_type(forward_relocation_request)			-> request;
gtp_msg_type(forward_relocation_response)			-> response;
gtp_msg_type(forward_relocation_complete_notification)		-> other;
gtp_msg_type(forward_relocation_complete_acknowledge)		-> other;
gtp_msg_type(forward_access_context_notification)		-> other;
gtp_msg_type(forward_access_context_acknowledge)		-> other;
gtp_msg_type(relocation_cancel_request)				-> request;
gtp_msg_type(relocation_cancel_response)			-> response;
gtp_msg_type(configuration_transfer_tunnel)			-> other;
gtp_msg_type(detach_notification)				-> other;
gtp_msg_type(detach_acknowledge)				-> other;
gtp_msg_type(cs_paging_indication)				-> other;
gtp_msg_type(ran_information_relay)				-> other;
gtp_msg_type(alert_mme_notification)				-> other;
gtp_msg_type(alert_mme_acknowledge)				-> other;
gtp_msg_type(ue_activity_notification)				-> other;
gtp_msg_type(ue_activity_acknowledge)				-> other;
gtp_msg_type(isr_status_indication)				-> other;
gtp_msg_type(create_forwarding_tunnel_request)			-> request;
gtp_msg_type(create_forwarding_tunnel_response)			-> response;
gtp_msg_type(suspend_notification)				-> other;
gtp_msg_type(suspend_acknowledge)				-> other;
gtp_msg_type(resume_notification)				-> other;
gtp_msg_type(resume_acknowledge)				-> other;
gtp_msg_type(create_indirect_data_forwarding_tunnel_request)	-> request;
gtp_msg_type(create_indirect_data_forwarding_tunnel_response)	-> response;
gtp_msg_type(delete_indirect_data_forwarding_tunnel_request)	-> request;
gtp_msg_type(delete_indirect_data_forwarding_tunnel_response)	-> response;
gtp_msg_type(release_access_bearers_request)			-> request;
gtp_msg_type(release_access_bearers_response)			-> response;
gtp_msg_type(downlink_data_notification)			-> other;
gtp_msg_type(downlink_data_notification_acknowledge)		-> other;
gtp_msg_type(pgw_restart_notification)				-> other;
gtp_msg_type(pgw_restart_notification_acknowledge)		-> other;
gtp_msg_type(update_pdn_connection_set_request)			-> request;
gtp_msg_type(update_pdn_connection_set_response)		-> response;
gtp_msg_type(mbms_session_start_request)			-> request;
gtp_msg_type(mbms_session_start_response)			-> response;
gtp_msg_type(mbms_session_update_request)			-> request;
gtp_msg_type(mbms_session_update_response)			-> response;
gtp_msg_type(mbms_session_stop_request)				-> request;
gtp_msg_type(mbms_session_stop_response)			-> response;
gtp_msg_type(_)							-> other.

gtp_msg_response(echo_request)						-> echo_response;
gtp_msg_response(create_session_request)				-> create_session_response;
gtp_msg_response(delete_session_request)				-> delete_session_response;
gtp_msg_response(modify_bearer_request)					-> modify_bearer_response;
gtp_msg_response(change_notification_request)				-> change_notification_response;
gtp_msg_response(create_bearer_request)					-> create_bearer_response;
gtp_msg_response(update_bearer_request)					-> update_bearer_response;
gtp_msg_response(delete_bearer_request)					-> delete_bearer_response;
gtp_msg_response(delete_pdn_connection_set_request)			-> delete_pdn_connection_set_response;
gtp_msg_response(identification_request)				-> identification_response;
gtp_msg_response(context_request)					-> context_response;
gtp_msg_response(forward_relocation_request)				-> forward_relocation_response;
gtp_msg_response(relocation_cancel_request)				-> relocation_cancel_response;
gtp_msg_response(create_forwarding_tunnel_request)			-> create_forwarding_tunnel_response;
gtp_msg_response(create_indirect_data_forwarding_tunnel_request)	-> create_indirect_data_forwarding_tunnel_response;
gtp_msg_response(delete_indirect_data_forwarding_tunnel_request)	-> delete_indirect_data_forwarding_tunnel_response;
gtp_msg_response(release_access_bearers_request)			-> release_access_bearers_response;
gtp_msg_response(update_pdn_connection_set_request)			-> update_pdn_connection_set_response;
gtp_msg_response(mbms_session_start_request)				-> mbms_session_start_response;
gtp_msg_response(mbms_session_update_request)				-> mbms_session_update_response;
gtp_msg_response(mbms_session_stop_request)				-> mbms_session_stop_response;
gtp_msg_response(Response)						-> Response.

%%%===================================================================
%%% Internal functions
%%%===================================================================

map_reply_ies(IEs) when is_list(IEs) ->
    [map_reply_ie(IE) || IE <- IEs];
map_reply_ies(IE) ->
    [map_reply_ie(IE)].

map_reply_ie(request_accepted) ->
    #v2_cause{v2_cause = request_accepted};
map_reply_ie(not_found) ->
    #v2_cause{v2_cause = context_not_found};
map_reply_ie({mandatory_ie_missing, {_IE, _Instance}}) ->
    #v2_cause{v2_cause = mandatory_ie_missing};
map_reply_ie(IE)
  when is_tuple(IE) ->
    IE.

