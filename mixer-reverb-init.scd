var initMixers = {
	// It's weird, but MixerChannel uses ServerTree to rebuild mixers.
	// If I create mixers while ServerTree is still pending, then you get
	// both the normal mixer init and ServerTree's attempt to reconstruct.
	// So I have to delay mixer creation until MixerChannelReconstructor is done
	{
		while { MixerChannelReconstructor.isRunning } { 0.2.wait };

		if(BusDict.controlNames[s].isNil or: { BusDict.controlNames[s].every(_ != \reserved2) }) {
			BusDict.control(s, 2, \reserved2);
			// BusDict.control(z, 2, \reserved2);
		};

		SynthDef(\cll_freeverb2, { |out, mix = 0.25, room = 0.15, damp = 0.5, amp = 1|
			var in = In.ar(out, 2);
			ReplaceOut.ar(out, FreeVerb2.ar(in[0], in[1], mix, room, damp, amp));
		}).add;

		if((~master.tryPerform(\isRunning) ? false).not) {
			~master = MixerChannel(\master, s, 2, 2, level: 1);
		};

		if((~rvbmc.tryPerform(\isRunning) ? false).not) {
			~rvbmc = MixerChannel(\rvb, s, 2, 2, level: 1, outbus: ~master);
		};

		~rvbmc.doWhenReady {
			if(~rvb.isPlaying.not) {
				s.makeBundle(s.latency, {
					~rvb = ~rvbmc.playfx(\cll_freeverb2, [mix: 1.0, room: 0.8921568627451, damp: 0.25, amp: 1.0]);
				});
			};
		};

		if((~shortrvbmc.tryPerform(\isRunning) ? false).not) {
			~shortrvbmc = MixerChannel(\shortrvb, s, 2, 2, level: 1, outbus: ~master);
		};

		~shortrvbmc.doWhenReady {
			if(~shortrvb.isPlaying.not) {
				s.makeBundle(s.latency, {
					~shortrvb = ~shortrvbmc.playfx(\cll_freeverb2, [mix: 1.0, room: 0.68, damp: 0.48, amp: 1.0]);
					MultiEQ.new(2, \eq, 8544.433, -7.97.dbamp, 0.115).play(~shortrvbmc);
				});
			}
		};

	}.fork(SystemClock);

	// init once only
	ServerTree.remove(initMixers, Server.default);
};

if(Server.default.serverRunning) {
	initMixers.value;
} {
	ServerTree.add(initMixers, Server.default);
};