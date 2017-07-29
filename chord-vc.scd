Instr([\busfx, \chorus2], { arg bus, numInChan, numOutChan, numDelays, predelay, speed, depth, ph_diff, preamp;
	var in, sig, mods;
	in = In.ar(bus, numInChan) * preamp;
	mods = { |i|
		SinOsc.kr(speed * rrand(0.9, 1.1), ph_diff * i, depth, predelay);
	} ! (numDelays * numOutChan);
	sig = DelayC.ar(in, 0.5, mods);
	Mix(sig.clump(numOutChan))
}, [\audiobus, \numChannels, \numChannels, \numChannels, [0.0001, 0.2, \exponential, 0, 0.001], [0.001, 10, \exponential], [0.0001, 0.25, \exponential], [0, 2*pi], [0.1, 10, \exp, 0, 1]]);

(
{
	var makeSynth = { |name, oscfunc, n(6)|
		SynthDef(name, { |out, /*gate = 1,*/ freq = 440, detun = 1.008, // pWidth = 0.254,
			ffreq = 2000, gain = 0, fegRatio = 3, fAtk = 0.005, fDcy = 0.2,
			amp = 0.1, dcy = 0.4, panCenter = 0, panWidth = 0.8,
			inharmonicity = 0, acc = 0, accAmt = 1.5, accAmp = 1.5|
			var rdetun = detun.reciprocal,
			detunes = Array.fill(n, { Rand(0, 1).linexp(0, 1, rdetun, detun) }),
			top = min(fegRatio * ((accAmt - 1) * acc + 1), 18000 / ffreq),
			feg = EnvGen.kr(Env.perc(fAtk, fDcy, top, [1, -3])),
			eg = EnvGen.kr(Env.perc(0.005, dcy), doneAction: 2),
			shift = freq * Rand(inharmonicity.neg, inharmonicity),
			sig = SynthDef.wrap(oscfunc, prependArgs: [freq * detunes - shift]);
			sig = Splay.ar(sig, min(panWidth, panCenter.abs - panWidth), 1, panCenter);
			// can't make this an fx synth b/c osc freq must compensate
			sig = FreqShift.ar(sig, shift);
			sig = MoogFF.ar(sig, ffreq * feg, gain);
			amp = amp * (accAmp - 1 * acc + 1);
			Out.ar(out, sig * (amp * eg));
		}).add;
	};

	makeSynth.(\pulsepluck, { |freq, pWidth = 0.254| Pulse.ar(freq, pWidth) });
	makeSynth.(\sawpluck, { |freq| Saw.ar(freq) });

	(
		keys: #[master, rvbmc],
		initLevel: -4.8.dbamp, // -12.dbamp,
		rvbLevel: -6.dbamp,
		defname: \pulsepluck,
		argPairs: [accAmt: 5, amp: 0.5],
		make: { |name|
			var out;
			~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
				chan.newPostSend(~rvbmc, ~rvbLevel);
			});

			out = Voicer(15, ~defname, args: [fegRatio: 12], target: ~target);
			out.mapGlobal(\ffreq, nil, 460, \freq);
			// out.mapGlobal(\fegRatio, nil, 10, [1, 30, \exp]);
			out.mapGlobal(\fAtk, nil, 0.002, [0.002, 0.08, \exp]);
			out.mapGlobal(\fDcy, nil, 0.12, [0.01, 1, \exp]);
			out.mapGlobal(\gain, nil, 0, [0, 3.9], allowGUI: false);
			out.mapGlobal(\inharmonicity, nil, 0, [0, 0.4]);
			out
		},
		free: { ~target.free },
		type: \vc
	) => Fact(\staccVC);
}.value;
);


(
// Klanks (Ferguson)
SynthDef(\klanky, { |out, bufnum, freq = 440, amp = 0.1, time = 0.1,
	ratios = #[1, 2, 3, 4, 5], amps = #[1, 0.5, 0.333, 0.25, 0.2],
	excFreq = 50, beats = 0, excTime = 0.05,
	// not really "gate" -- voicer's velocity interface
	pan = 0, width = 0, gate = 0.1, vsens = 0.5, vTimeSens = 0.5|
	var gateLatch = Latch.kr(gate, gate),
	realAmp = amp * Sensitivity.kr(1, gateLatch, vsens),
	exc = COsc.ar(bufnum, excFreq, beats, realAmp) * EnvGen.ar(Env.perc(0.01, excTime)),
	panShuf = Dshuf((0 .. ratios.size-1)),
	initTrig = Impulse.kr(0),
	panLeft, panIncr, sig;
	width = min(width, 1 - abs(pan));
	panIncr = width / (ratios.size-1);
	panLeft = pan - width;
	time = time * Sensitivity.kr(1, gateLatch, vTimeSens);
	sig = Mix(ratios.collect { |ratio, i|
		var panIndex = Demand.kr(initTrig, 0, panShuf);
		Pan2.ar(Ringz.ar(exc, freq * ratio, time, amps[i]), panLeft + (panIndex * panIncr));
	});
	DetectSilence.ar(sig.sum, 0.001, doneAction: 2);
	Out.ar(out, sig);
}).add;

(
keys: #[master, rvbmc],
initLevel: -13.5.dbamp,
rvbLevel: -2.42.dbamp,
eventKey: \voicerNote,
bufData: {
	// Pink noise == 1/f noise <-- Voss algorithm == Pvoss
	// Random generation will have DC offset.
	// Easiest removal is to subtract the DC offset (data.sum)
	// distributed over all samples (data.sum / data.size == data.mean).
	var n = 1024,
	stream = Pvoss(0, 1, 16, n).asStream,
	data = Signal.fill(n, stream);  // value is implicit
	data - data.mean
},
argPairs: { |thisVC|
	Pbind(
		\ratios, (BPStream(\ratioBase) + (
			Pwhite(
				thisVC.v.globalControls[\pRandWidth].asPattern.neg,
				thisVC.v.globalControls[\pRandWidth].asPattern, inf
			) * Pn(Pgeom.fromEndpoints(0.05, 1, 5), inf)
		).clump(5)).collect([_]),
		\pan, BPStream(\pan),
		\length, inf,  // don't send a release
		\time, BPStream(\time),
		\excFreq, BPStream(\excFreq),
		\beats, BPStream(\beats)
	)
},
extraChildParms: (  // these go into the ~child environment
	ratioBase: (1..5),
	pan: 0,
	time: 1,
	excFreq: Pexprand(40, 75, inf),
	beats: Pexprand(1.5, 12.5, inf)
),
make: { |name|
	var out, data;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		chan.newPostSend(~rvbmc, ~rvbLevel);
	});
	data = ~bufData.value;
	if(data.respondsTo(\asWavetable).not) { data = data.as(Signal) };
	~buf = Buffer.sendCollection(s, data.asWavetable, 1);
	// override default Event's bufnum == 0
	// ~extraParms = ~extraParms.copy.put(\bufnum, ~buf.bufnum);
	out = Voicer(20, \klanky, [
		bufnum: ~buf.bufnum,
		excTime: 0.5,
	], target: ~target);
	out.mapGlobal(\beats, nil, 1.5, [0, 50, 3]);
	// out.mapGlobal(\excTime, nil, 0.05, [0.01, 0.2, 3]);
	out.mapGlobal(\vTimeSens, nil, 0.8, [0, 1]);
	out.mapGlobal(\width, nil, 0, [0, 1]);
	out.mapGlobal(\pRandWidth, nil, 0, [0, 0.4]);
	defer(e { \vcToDefaultBP.eval(name, ~defaultBP) }, 0.25);
	out
},
free: { [~target, ~buf].free },
type: \vc, defaultName: \klc/*, defaultBP: \ch*/) => Fact(\klankVC);
);


(
SynthDef(\fmpad, { |out, gate = 1, freq = 440, freqlag = 0.08,
	index = 1, ratio = 1, acc = 0, accMul = 3, mbuf, cbuf,
	detun = 1.01, t_rerand = 1,
	panCenter = 0, panWidth = 0.6, amp = 0.5,
	atk = 0.08, dcy = 0.3, sus = 0.6, rel = 1, modAmt = 0, modDcy = 0.5|
	var n = 8,
	r_detun = detun.reciprocal,
	detunes = Array.fill(n, { TRand.kr(0, 1, t_rerand).linexp(0, 1, r_detun, detun) }),
	indexEg = EnvGen.kr(Env([0, acc * modAmt, 0], [atk, modDcy], -3), gate),
	accent = accMul + 1,
	laggedFreq = Lag.kr(freq, freqlag),
	mods = Osc.ar(mbuf, laggedFreq * ratio * detunes, mul: index * accent * (1 + indexEg)),
	cars = Osc.ar(cbuf, laggedFreq * detunes * (1 + mods)),
	width = min(panWidth, 1.0 - abs(panCenter)),

	sig = Splay.ar(cars, width, amp, panCenter),
	eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2);

	Out.ar(out, sig * (eg * amp));
}).add;

(
keys: #[master, rvbmc],
initLevel: -16.2.dbamp,
rvbLevel: -5.3.dbamp,
argPairs: [amp: 0.5],
modHrm: (1..4).reciprocal,
carHrm: #[1, 1, 1],
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		chan.newPostSend(~rvbmc, ~rvbLevel);
	});

	~mbuf = Buffer.alloc(s, 2048, 1, { |buf| buf.sine1Msg(~modHrm.value) });
	~cbuf = Buffer.alloc(s, 2048, 1, { |buf| buf.sine1Msg(~carHrm.value) });

	out = Voicer(20, \fmpad, [mbuf: ~mbuf.bufnum, cbuf: ~cbuf.bufnum, amp: 0.5], target: ~target);
	out.mapGlobal(\index, nil, 0.392, [0.1, 10, \exp]);
	out.mapGlobal(\ratio, nil, 2, SnapControlSpec(1, 10, \lin, 1).snap_(0.15));
	out.mapGlobal(\modAmt, nil, 1.5, [0, 3]);
	out
},
free: { [~target, ~cbuf, ~mbuf].free },
type: \vc) => Fact(\fmpadVC);
);


(
SynthDef(\fmbrass, { |out, freq = 220, gate = 1, t_gate = 1, amp = 0.1, cbuf, mbuf,
	freqlag = 0.1, detun = 1.008, panCenter = 0, panWidth = 1, acc = 0, accAmt = 5,
	ratio = 1, index = 1, modEgAmt = 1.96, modAtk = 0.0511, modDcy = 0.0793|
	var n = 6;
	var modEg = EnvGen.kr(Env([0, (acc * accAmt) + modEgAmt, 0], [modAtk, modDcy], -2), t_gate),
	laggedFreq = Lag.kr(freq, freqlag),
	randFreq = Array.fill(n, { laggedFreq * (detun ** Rand(-1.0, 1.0)) }),
	mod = Osc.ar(mbuf, randFreq * ratio, mul: index * (1 + modEg)),
	car = Osc.ar(cbuf, randFreq * (1 + mod), mul: amp),
	eg = EnvGen.kr(Env.adsr(0.1, 0.3, 0.5, 0.2), gate, doneAction: 2);
	car = Splay.ar(car, panWidth, center: panCenter);
	Out.ar(out, car * eg);
}).add;

(
keys: #[master, rvbmc],
initLevel: -12.dbamp,
rvbLevel: -1.dbamp,
argPairs: [amp: 0.25],
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		MultiEQ.new(2, \eq, 279.743, -3.759.dbamp, 1, \eq, 10341.84, 3.759.dbamp, 1).play(chan);
		~chorus = chan.playfx(Instr("busfx.chorus2"), [0, 2, 2, 3, 0.013676047024487, 0.24669302064117, 0.0076241645277023, 2.0019953184641, 0.7290294928589]);
		~chorus.doWhenPlaying {
			~chorus.synth.moveToTail(chan.effectgroup);
		};
		chan.newPostSend(~rvbmc, ~rvbLevel);
	});
	~cbuf = Buffer.alloc(s, 4096, 1, completionMessage: { |buf|
		buf.sine1Msg((1..5).reciprocal.squared)
	});
	~mbuf = Buffer.alloc(s, 4096, 1, completionMessage: { |buf| buf.sine1Msg(#[1]) });
	out = Voicer(25, \fmbrass, [
		cbuf: ~cbuf.bufnum, mbuf: ~mbuf.bufnum
	], target: ~target);
	out.mapGlobal(\index, nil, 1.25, #[0.1, 20, \exp]);
	out.mapGlobal(\modEgAmt, nil, 0.81, #[0, 10]);
	out.mapGlobal(\accAmt, nil, 2.5, #[0, 10]);
	out
},
free: { [~target, ~cbuf, ~mbuf].free },
type: \vc) => Fact(\fmbrassVC);
);


(
SynthDef(\fmclav, { |out, /*gate = 1,*/ amp = 0.1, cbuf, mbuf,
	freq = 440, detun = 1.008,
	index = 1, modAmt = 1, modDcy = 1, maxIndex = 7, acc = 0, accMul = 1,
	sus = 0.6, dcy = 0.08, rel = 2, width = 0.8, panCenter = 0,
	ratios = #[1, 2, 4, 8.5]|
	var n = 8,
	r_detun = detun.reciprocal,
	detunes = Array.fill(n, { ExpRand(r_detun, detun) }),
	initTrig = Impulse.kr(0),
	// in principle, slight variability by positioning ratios randomly each time
	// in practice, this is purely for vanity
	ratioGen = Dseq([Dshuf(ratios, 1)], inf),
	ratioSpread = Array.fill(n, { Demand.kr(initTrig, 0, ratioGen) }),
	maxAmt = max(0, maxIndex / index - 1),
	modEg = EnvGen.kr(Env.perc(0.01, modDcy)) * (min(maxAmt, modAmt) * ((acc * accMul) + 1)) + 1,
	detunedFreqs = detunes * freq,
	mod = Osc.ar(mbuf, detunedFreqs * ratioSpread, 0, index * modEg),
	car = Osc.ar(cbuf, detunedFreqs * (1 + mod)),
	eg = EnvGen.kr(Env([0, 1, sus, 0], [0.003, dcy, rel], -2), doneAction: 2);
	car = Splay.ar(car, width, amp, panCenter);
	Out.ar(out, car * eg);
}).add;

(
keys: #[master, rvbmc],
initLevel: -12.dbamp,
rvbLevel: -6.dbamp,
argPairs: [amp: 0.5],
modHrm: (1..4).reciprocal,
carHrm: #[1],
fxFunc: nil,
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		chan.newPostSend(~rvbmc, ~rvbLevel);
		~fxFunc.(chan);
	});
	~mbuf = Buffer.alloc(s, 2048, 1, { |buf| buf.sine1Msg(~modHrm) });
	~cbuf = Buffer.alloc(s, 2048, 1, { |buf| buf.sine1Msg(~carHrm) });
	out = Voicer(20, \fmclav, [mbuf: ~mbuf.bufnum, cbuf: ~cbuf.bufnum], target: ~target);
	out.mapGlobal(\index, nil, 2.5, [0.5, 20, \exp]);
	out.mapGlobal(\accMul, nil, 1, [0, 3]);
	out.mapGlobal(\detun, nil, 1.01, \mydetune);
	out
},
free: { [~target, ~cbuf, ~mbuf].free },
type: \vc) => Fact(\fmclavVC);
);


{
	var makeSynth = { |name, oscFunc, n(6)|
		SynthDef(name, { |out, gate = 1, freq = 440, detun = 1.008, amp = 0.1,
			ffreq = 2000, rq = 1, fmodAmt = 2, fmodAtk = 0.01, fmodDcy = 1,
			panCenter = 0, panWidth = 0.8, freqlag = 0.1,
			atk = 0.05, dcy = 0.2, sus = 0.6, rel = 1|
			var detunes = Array.fill(n, { detun ** Rand(-1, 1) }),
			freqs = Lag.kr(freq, freqlag) * detunes,
			sig = SynthDef.wrap(oscFunc, prependArgs: [freqs]),
			feg = EnvGen.kr(Env([0, 1, 0], [fmodAtk, fmodDcy], -4), gate),
			eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2);
			sig = Splay.ar(sig, panWidth, amp, panCenter);
			sig = RLPF.ar(sig, (ffreq * (1 + (fmodAmt * feg))).clip(20, 20000), rq);
			Out.ar(out, sig * eg);
		}).add;
	};

	makeSynth.(\sawpad, { |freqs| Saw.ar(freqs) });
	makeSynth.(\pulsepad, { |freqs, pwidth = 0.5| Pulse.ar(freqs, pwidth) });
	makeSynth.(\mixedpad, { |freqs, pwidth = 0.5|
		freqs.collect { |freq, i|
			if(i.even) { Saw.ar(freq) } { Pulse.ar(freq, pwidth) }
		}
	});

	(
		keys: #[master, rvbmc],
		initLevel: -12.dbamp,
		rvbLevel: -6.dbamp,
		defname: \mixedpad,
		ffreq: 361.23244647798,
		rq: 0.84594594594595,
		detun: 1.0055606242111,
		fmodAtk: 0.59372509113479,
		fmodDcy: 3.1902009819793,
		atk: 0.66088520044072,
		dcy: 1.2987158009894,
		fmodAmt: 0.2564799643352,
		pwdith: 0.5,
		make: { |name|
			var out;
			~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
				chan.newPostSend(~rvbmc, ~rvbLevel);
			});

			out = Voicer(20, ~defname, [
				detun: ~detun,
				fmodAtk: ~fmodAtk,
				fmodDcy: ~fmodDcy,
				atk: ~atk,
				dcy: ~dcy,
				fmodAmt: ~fmodAmt
			], target: ~target);
			out.mapGlobal(\ffreq, nil, ~ffreq, \freq);
			out.mapGlobal(\rq, nil, ~rq, \myrq);
			out
		},
		free: { ~target.free },
		type: \vc) => Fact(\anapadVC);
}.value;
