%% Copyright 2015, Travelping GmbH <info@travelping.com>

%% This program is free software; you can redistribute it and/or
%% modify it under the terms of the GNU General Public License
%% as published by the Free Software Foundation; either version
%% 2 of the License, or (at your option) any later version.

-module(gtp_context).

-compile({parse_transform, do}).

-export([lookup/1, new/5, handle_message/5, start_link/4,
	 setup/2, update/3, teardown/2, handle_recovery/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include_lib("gtplib/include/gtp_packet.hrl").
-include("include/ergw.hrl").

%%====================================================================
%% API
%%====================================================================

lookup(TEI) ->
    gtp_context_reg:lookup(TEI).

new(Type, IP, Port, GtpPort,
    #gtp{version = Version, ie = IEs} = Msg) ->
    Protocol = get_protocol(Type, Version),
    do([error_m ||
	   Interface <- get_interface_type(Version, IEs),
	   Context <- gtp_context_sup:new(GtpPort, Protocol, Interface),
	   gen_server:cast(Context, {handle_message, IP, Port, Msg})
       ]).

handle_message(Type, IP, Port, GtpPort, #gtp{version = Version, tei = TEI} = Msg) ->
    case lookup(TEI) of
	Context when is_pid(Context) ->
	    gen_server:cast(Context, {handle_message, IP, Port, Msg});
	_ ->
	    Protocol = get_protocol(Type, Version),
	    Reply = Protocol:build_response({Msg#gtp.type, not_found}),
	    Data = gtp_packet:encode(Reply#gtp{seq_no = Msg#gtp.seq_no}),
	    lager:debug("gtp_context send ~s error to ~w:~w: ~p, ~p", [Protocol:type(), IP, Port, Reply, Data]),
	    gtp:send(GtpPort, Protocol:type(), IP, Port, Data)
    end.

start_link(GtpPort, Protocol, Interface, Opts) ->
    gen_server:start_link(?MODULE, [GtpPort, Protocol, Interface], Opts).

%%====================================================================
%% gen_server API
%%====================================================================

init([GtpPort, Protocol, Interface]) ->
    {ok, TEI} = gtp_c_lib:alloc_tei(),

    State = #{
      gtp_port  => GtpPort,
      protocol  => Protocol,
      interface => Interface,
      tei       => TEI},
    {ok, State}.

handle_call(Request, _From, State) ->
    lager:warning("handle_call: ~p", [lager:pr(Request, ?MODULE)]),
    {reply, ok, State}.

handle_cast({handle_message, IP, Port, #gtp{type = Type, ie = IEs} = Msg}, State) ->
    lager:debug("~w: handle gtp: ~w, ~p",
		[?MODULE, Port, gtp_c_lib:fmt_gtp(Msg)]),

    Spec = request_spec(Type, State),
    {Req, Missing} = gtp_c_lib:build_req_record(Type, Spec, IEs),
    lager:debug("Mis: ~p", [Missing]),

    case gtp_msg_type(Type, State) of
	response when Missing /= [] ->
	    %% ignore reply with missing mandarory arguments
	    {noreply, State};

	response ->
	    handle_response(Msg, State);

	_ when Missing /= [] ->
	    handle_error(IP, Port, Msg, {mandatory_ie_missing, hd(Missing)}, State);

	_ ->

	    handle_request(IP, Port, Msg, Req, State)
    end;

handle_cast(Msg, State) ->
    lager:error("~w: handle_cast: ~p", [?MODULE, lager:pr(Msg, ?MODULE)]),
    {noreply, State}.

handle_info(Info, State) ->
    lager:debug("handle_info: ~p", [lager:pr(Info, ?MODULE)]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Message Handling functions
%%%===================================================================

handle_error(IP, Port, #gtp{type = Type, seq_no = SeqNo}, Reply, State) ->
    Response = build_response({Type, Reply}, State),
    send_message(IP, Port, Response#gtp{seq_no = SeqNo}, State),
    {noreply, State}.

handle_request(IP, Port, #gtp{version = Version, seq_no = SeqNo} = Msg, Req, State0) ->
    lager:debug("GTP~s ~s:~w: ~p",
		[Version, inet:ntoa(IP), Port, gtp_c_lib:fmt_gtp(Msg)]),

    try interface_handle_request(Msg, Req, State0) of
	{reply, Reply, State1} ->
	    Response = build_response(Reply, State1),
	    send_message(IP, Port, Response#gtp{seq_no = SeqNo}, State1),
	    {noreply, State1};

	{stop, Reply, State1} ->
	    Response = build_response(Reply, State1),
	    send_message(IP, Port, Response#gtp{seq_no = SeqNo}, State1),
	    {stop, normal, State1};

	{error, Reply} ->
	    Response = build_response(Reply, State0),
	    send_message(IP, Port, Response#gtp{seq_no = SeqNo}, State0),
	    {noreply, State0};

	{noreply, State1} ->
	    {noreply, State1};

	Other ->
	    lager:error("handle_request failed with: ~p", [Other]),
	    {noreply, State0}
    catch
	Class:Error ->
	    Stack  = erlang:get_stacktrace(),
	    lager:error("GTP~p failed with: ~p:~p (~p)", [Version, Class, Error, Stack]),
	    {noreply, State0}
    end.

handle_response(Msg, #{path := Path} = State) ->
    gtp_path:handle_response(Path, Msg),
    {noreply, State}.

send_message(IP, Port, Msg, #{gtp_port := GtpPort, protocol := Protocol} = State) ->
    %% TODO: handle encode errors
    try
        Data = gtp_packet:encode(Msg),
	lager:debug("gtp_context send ~s to ~w:~w: ~p, ~p", [Protocol:type(), IP, Port, Msg, Data]),
	gtp:send(GtpPort, Protocol:type(), IP, Port, Data)
    catch
	Class:Error ->
	    Stack  = erlang:get_stacktrace(),
	    lager:error("gtp send failed with ~p:~p (~p)", [Class, Error, Stack])
    end,
    State.

%%%===================================================================
%%% API Module Helper
%%%===================================================================

setup(#context{
	 control_ip  = RemoteCntlIP,
	 data_tunnel = gtp_v1_u,
	 data_ip     = RemoteDataIP,
	 data_tei    = RemoteDataTEI,
	 ms_v4       = MSv4},
      #{gtp_port  := GtpPort,
	protocol  := CntlProtocol,
	interface := Interface,
	tei       := LocalTEI}) ->

    ok = gtp:create_pdp_context(GtpPort, 1, RemoteDataIP, MSv4, LocalTEI, RemoteDataTEI),
    gtp_path:register(GtpPort, Interface, CntlProtocol, RemoteCntlIP, gtp_v1_u, RemoteDataIP),
    ok.

update(#context{
	  control_ip  = RemoteCntlIPNew,
	  data_tunnel = gtp_v1_u,
	  data_ip     = RemoteDataIPNew,
	  data_tei    = RemoteDataTEINew,
	  ms_v4       = MSv4},
        #context{
	    control_ip  = RemoteCntlIPOld,
	    data_tunnel = gtp_v1_u,
	    data_ip     = RemoteDataIPOld,
	    ms_v4       = MSv4},
	 #{gtp_port  := GtpPort,
	   protocol  := CntlProtocol,
	   interface := Interface,
	   tei       := LocalTEI}) ->

    gtp_path:unregister(Interface, CntlProtocol, RemoteCntlIPOld, gtp_v1_u, RemoteDataIPOld),
    ok = gtp:update_pdp_context(GtpPort, 1, RemoteDataIPNew, MSv4, LocalTEI, RemoteDataTEINew),
    gtp_path:register(GtpPort, Interface, CntlProtocol, RemoteCntlIPNew, gtp_v1_u, RemoteDataIPNew),
    ok.

teardown(#context{
	    control_ip  = RemoteCntlIP,
	    data_tunnel = gtp_v1_u,
	    data_ip     = RemoteDataIP,
	    data_tei    = RemoteDataTEI,
	    ms_v4       = MSv4},
	 #{gtp_port  := GtpPort,
	   protocol  := CntlProtocol,
	   interface := Interface,
	   tei       := LocalTEI}) ->

    gtp_path:unregister(Interface, CntlProtocol, RemoteCntlIP, gtp_v1_u, RemoteDataIP),
    ok = gtp:delete_pdp_context(GtpPort, 1, RemoteDataIP, MSv4, LocalTEI, RemoteDataTEI).

handle_recovery(RecoveryCounter,
		#context{
		   control_ip  = RemoteCntlIP,
		   data_tunnel = gtp_v1_u,
		   data_ip     = RemoteDataIP},
		#{gtp_port  := GtpPort,
		  protocol  := CntlProtocol,
		  interface := Interface}) ->
    gtp_path:handle_recovery(RecoveryCounter, GtpPort, Interface, CntlProtocol, RemoteCntlIP, gtp_v1_u, RemoteDataIP).

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_protocol('gtp-u', v1) ->
    gtp_v1_u;
get_protocol('gtp-c', v1) ->
    gtp_v1_c;
get_protocol('gtp-c', v2) ->
    gtp_v2_c.

get_interface_type(v1, _) ->
    {ok, ggsn_gn};
get_interface_type(v2, IEs) ->
    case find_ie(v2_fully_qualified_tunnel_endpoint_identifier, 0, IEs) of
	#v2_fully_qualified_tunnel_endpoint_identifier{interface_type = IfType} ->
	     map_v2_iftype(IfType);
	_ ->
	    {error, {mandatory_ie_missing, {v2_fully_qualified_tunnel_endpoint_identifier, 0}}}
    end.

find_ie(_, _, []) ->
    undefined;
find_ie(Type, Instance, [IE|_])
  when element(1, IE) == Type,
       element(2, IE) == Instance ->
    IE;
find_ie(Type, Instance, [_|Next]) ->
    find_ie(Type, Instance, Next).

apply_mod(Key, F, A, State) ->
    M = maps:get(Key, State),
    apply(M, F, A).

gtp_msg_type(Type, State) ->
    apply_mod(protocol, gtp_msg_type, [Type], State).

request_spec(Type, State) ->
    apply_mod(interface, request_spec, [Type], State).

interface_handle_request(Msg, Req, State) ->
    apply_mod(interface, handle_request, [Msg, Req, State], State).

build_response(Reply, State) ->
    apply_mod(protocol, build_response, [Reply], State).

map_v2_iftype(6)  -> {ok, pgw_s5s8};
map_v2_iftype(34) -> {ok, pgw_s2a};
map_v2_iftype(_)  -> {error, unsupported}.
