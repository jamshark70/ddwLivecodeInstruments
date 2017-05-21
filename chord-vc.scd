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
		initLevel: -12.dbamp,
		rvbLevel: -6.dbamp,
		defname: \pulsepluck,
		argPairs: [accAmt: 5],
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


