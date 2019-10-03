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

		SynthDef(\cll_freeverb2, { |out, mix = 0.25, room = 0.15, damp = 0.5, amp = 1, hpfreq = 200|
			var in = In.ar(out, 2);
			in = HPF.ar(in, hpfreq);
			ReplaceOut.ar(out, FreeVerb2.ar(in[0], in[1], mix, room, damp, amp));
		}).add;

		// \loadAllCl.eval takes half a second to evaluate (it's a LOT of code)
		// so server messages are late, causing the above synthdef not to be ready
		// so we wait until the def is there
		s.sync;

		if((~hwOut.tryPerform(\isRunning) ? false).not) {
			~hwOut = MixerChannel(\hwOut, s, 2, 2, level: 2.sqrt);  // +3 dB to offset Balance2
		};

		if((~master.tryPerform(\isRunning) ? false).not) {
			~master = MixerChannel(\master, s, 2, 2, level: 1, outbus: ~hwOut);
			~master.setControl(\clip, 6);
		};

		if((~rvbmc.tryPerform(\isRunning) ? false).not) {
			// used to go through ~master
			// now through ~hwOut, which is +3 dB louder; so, compensate by -3 dB
			~rvbmc = MixerChannel(\rvb, s, 2, 2, level: 0.5.sqrt, outbus: ~hwOut);
		};

		~rvbmc.doWhenReady {
			if(~rvb.isPlaying.not) {
				s.makeBundle(s.latency, {
					~rvb = ~rvbmc.playfx(\cll_freeverb2, [mix: 1.0, room: 0.8921568627451, damp: 0.25, amp: 1.0]);
				});
			};
		};

		if((~shortrvbmc.tryPerform(\isRunning) ? false).not) {
			~shortrvbmc = MixerChannel(\shortrvb, s, 2, 2, level: 0.5.sqrt, outbus: ~hwOut);
		};

		~shortrvbmc.doWhenReady {
			if(~shortrvb.isPlaying.not) {
				s.makeBundle(s.latency, {
					~shortrvb = ~shortrvbmc.playfx(\cll_freeverb2, [mix: 1.0, room: 0.68, damp: 0.48, amp: 1.0]);
					MultiEQ.new(2, \eq, 8544.433, -7.97.dbamp, 0.115).play(~shortrvbmc);
				});
			}
		};

		if((~longrvbmc.tryPerform(\isRunning) ? false).not) {
			~longrvbmc = MixerChannel(\rvb, s, 2, 2, level: 0.5.sqrt, outbus: ~hwOut);
		};

		~longrvbmc.doWhenReady {
			if(~longrvb.isPlaying.not) {
				s.makeBundle(s.latency, {
					~longrvb = ~longrvbmc.playfx(\cll_freeverb2, [mix: 1.0, room: 0.96, damp: 0.25, amp: 1.0]);
				});
			};
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
