// FM bass

SynthDef(\fmBass, { |out, freq = 440, gate = 1, t_gate = 1, amp = 0.1, cbuf, mbuf,
	ratio = 0.5, index = 3, detun = 1.003, bufmod = 0, bufmodlag = 0.1, freqlag = 0.08,
	indexDecay = 0.1, indexEgAmt = 0.62,
	preamp = 18, postamp = -11|
	var indexEg = EnvGen.kr(Env.perc(0.01, indexDecay), t_gate) * indexEgAmt,
	fLag = Lag.kr(freq, freqlag),
	mods = VOsc.ar(
		mbuf + Lag.kr(bufmod, bufmodlag),
		fLag * ratio * [1, detun],
		mul: index * (1 + indexEg)
	),
	cars = Osc.ar(cbuf, fLag * (1 + mods)),
	eg = EnvGen.kr(Env.adsr(0.01, 0.2, 0.6, 0.1), gate, doneAction: 2);
	cars = (cars * preamp.dbamp).tanh * postamp.dbamp;
	Out.ar(out, cars * (amp * eg));
}).add;

(
keys: #[master],
initLevel: -12.5.dbamp, // -8.6, 0.75,
argPairs: Pbind(
	\bufmod, Pwhite(0, 10.999, inf),
	\amp, 0.5,
),
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master,
		completionFunc: { |chan|
			~chorus = chan.playfx { |outbus,
				rate = 0.1, predelay = 0.05, width = 0.3, xfade = 0.5|
				var sig = In.ar(outbus, 2),
				wet = DelayC.ar(sig, 0.2,
					SinOsc.kr(
						rate * Array.fill(max(1, sig.size), { ExpRand(0.9, 1.11111) }),
						0, width * predelay, predelay
					)
				);
				XFade2.ar(sig, wet, xfade * 2 - 1)
			};
			~eq = MultiEQ(2, \bhipass, 104.018, 0.dbamp, 0.369).play(chan);
		}
	);
	~cbuf = Buffer.alloc(s, 2048, 1, completionMessage: { |buf| buf.sine1Msg(#[1]) });
	~mbufs = Buffer.allocConsecutive(12, s, 2048, 1, completionMessage: { |buf, i|
		var w = i.linlin(0, b.size-1, 0.16, 0.8);
		w = [w, 1.0 - w];
		buf.sine1Msg(Array.fill(20, { #[0, 1].wchoose(w) }).putFirst(1))
	});
	out = /*MonoPorta*/Voicer(2, \fmBass, [cbuf: ~cbuf.bufnum, mbuf: ~mbufs.first.bufnum], target: ~target);
	out.mapGlobal(\index, nil, 0.42, #[0.1, 100, \exp]);
	out.mapGlobal(\indexEgAmt, nil, 0, [0, 20, 3]);
	out
},
free: {
	[~target, ~cbuf, ~mbufs].free;
}, type: \vc) => Fact(\fmbassVC);


// pulse waves, kind of cheezy-analog-y
SynthDef(\pulseBass, { |out, freq = 440, gate = 1, t_gate = 1, freqlag = 0.1, freqRand = 1.008, amp = 0.1,
	widthRand = 0.3, widthCenter = 0.5, widthModRate = 0.3, widthModRand = 1.06,
	ffreq = 2000, fDecay = 0.1, fegAmt = 0, rq = 1, preamp = 0,
	atk = 0.01, dcy = 0.1, sus = 0.6, rel = 0.1|
	var numOscs = 4, lowRateRand = widthModRand.reciprocal, lowFRand = freqRand.reciprocal,
	fRand = Array.fill(numOscs, { TExpRand.kr(lowFRand, freqRand, t_gate) }),
	widths = Array.fill(numOscs, {
		LFDNoise3.kr(widthModRate * ExpRand(lowRateRand, widthModRand), widthRand, widthCenter)
	}),
	sig = Mix(Pulse.ar(Lag.kr(freq * fRand * 0.5, freqlag), widths)),  // randomizing on slur is lagged too
	feg = EnvGen.kr(Env.perc(0.01, fDecay), gate) * fegAmt + 1,
	eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2);
	sig = RLPF.ar(sig, (ffreq * feg).clip(20, 20000), rq);
	preamp = preamp.dbamp;
	sig = (sig * preamp).tanh / (preamp ** 0.6);
	Out.ar(out, (sig * (eg * amp)).dup);  // bass, don't pan
}).add;

(
keys: #[master],
initLevel: -12.dbamp, // -4.5.dbamp,
defname: \pulseBass,
argPairs: Pbind(\amp, 0.5),
gcSpecs: [
	[\ffreq, nil, 261.4, \freq],
	[\fDecay, nil, 0.17, [0, 2, 3]],
	[\fegAmt, nil, 5, [0, 5]],
	[\rq, nil, 1, \myrq],
	[\preamp, nil, -20, [-20, 5], false]
],
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		~eq = MultiEQ(2, \bhipass, 105.84, 0.dbamp, 0.474).play(chan);
	});
	out = /*MonoPorta*/Voicer(2, ~defname, [freqlag: 0.08], target: ~target);
	// out.portaTime = 0.08;
	~gcSpecs.do { |args| out.mapGlobal(*args) };
	out
},
free: { ~target.free },
type: \vc) => Fact(\pbsVC);

if('RLPFD'.asClass.notNil) {
	SynthDef(\pulseBass303, { |out, freq = 440, gate = 1, t_gate = 1, freqlag = 0.1, freqRand = 1.008, amp = 0.1,
		widthRand = 0.3, widthCenter = 0.5, widthModRate = 0.3, widthModRand = 1.06,
		ffreq = 2000, fDecay = 0.1, fegAmt = 0, res = 0, dist = 0,
		atk = 0.01, dcy = 0.1, sus = 0.6, rel = 0.1|
		var numOscs = 4, lowRateRand = widthModRand.reciprocal, lowFRand = freqRand.reciprocal,
		fRand = Array.fill(numOscs, { TExpRand.kr(lowFRand, freqRand, t_gate) }),
		widths = Array.fill(numOscs, {
			LFDNoise3.kr(widthModRate * ExpRand(lowRateRand, widthModRand), widthRand, widthCenter)
		}),
		sig = Mix(Pulse.ar(Lag.kr(freq * fRand * 0.5, freqlag), widths)),  // randomizing on slur is lagged too
		feg = EnvGen.kr(Env.perc(0.01, fDecay), gate) * fegAmt + 1,
		eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2);
		// mul: 3 as recommended by helpfile
		sig = RLPFD.ar(sig, (ffreq * feg).clip(20, 20000), res, dist, 6);
		Out.ar(out, (sig * (eg * amp)).dup);  // bass, don't pan
	}).add;

	Fact(\pbsVC).v.copy
	.put(\defname, \pulseBass303)
	.put(\gcSpecs, [
		[\ffreq, nil, 261.4, \freq],
		[\fDecay, nil, 0.17, [0, 2, 3]],
		[\fegAmt, nil, 5, [0, 5]],
		[\res, nil, 0, [0, 1]],
		[\dist, nil, 0, [0, 1], false]  // no autoGUI for this one
	]) => Fact(\pbs3VC);
};

// distorted sinewaves, a bit colder
SynthDef(\distBass, { |out, freq = 440, gate = 1, t_gate = 1, freqlag = 0.1, freqRand = 1.008, amp = 0.1,
	preamp = 0.1, bufnum = 0, preTanhAmp = 20,
	ffreq = 2000, fDecay = 0.1, fegAmt = 0, startRq = 1, endRq = 1, rqDecay = 0.1, rqCurve = 3,
	atk = 0.01, dcy = 0.1, sus = 0.6, rel = 0.1,
	delay = 0.012|
	var numOscs = 4, lowFRand = freqRand.reciprocal,
	fRand = Array.fill(numOscs, { TExpRand.kr(lowFRand, freqRand, t_gate) }),
	sig = SinOsc.ar(Lag.kr(freq * fRand, freqlag)),  // randomizing on slur is lagged too
	oscMix = Mix(sig),
	feg = EnvGen.kr(Env.perc(0.01, fDecay), gate) * fegAmt + 1,
	rqeg = EnvGen.kr(Env([startRq, endRq], [rqDecay], rqCurve * sign(endRq - startRq)), gate),
	eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2),
	preDistAmp, distAmp, ampCorrect;
	sig = Shaper.ar(bufnum, sig * preamp);
	// decorrelate
	sig.do { |chan, i|
		if(#[1, 2].includes(i % 4)) {
			sig[i] = DelayC.ar(chan, 0.1, SinOsc.kr(Rand(0.1, 0.2), Rand(0, pi), delay * 0.5, delay));
		};
	};
	sig = Mix((sig * (preamp * preTanhAmp)).tanh.clump(2));  // independently distort sinewaves
	// volume changes with preamp -- compensate by RMS ratio
	// mean would divide both by the same amount, which cancels out, so omit the mean division
	preDistAmp = RunningSum.ar(oscMix.squared, 441).sqrt;
	distAmp = RunningSum.ar(sig[0].squared, 441).sqrt;
	ampCorrect = min(1, preDistAmp / distAmp);
	sig = RLPF.ar(sig, (ffreq * feg).clip(20, 20000), rqeg);
	Out.ar(out, (sig * (eg * amp * ampCorrect)));
}).add;

(
keys: #[master],
initLevel: -22.dbamp,  // for some reason, this synth is LOUD
argPairs: [amp: 0.5],
endRate: 12,
makeShapeTable: { |endRate = 12|
	var out = Array.new,
	theta = 0.0,
	n = 512,
	baseRate = 2pi / n;

	while { theta < 6pi } {
		out = out.add(sin(theta));
		theta = theta + (baseRate * theta.linexp(0, 6pi, 1, endRate));
	};

	out = (out.drop(1).reverse).neg ++ out;
	out.resamp1(2048)
},
make: { |name|
	var out;
	~shapeBuf = Buffer.sendCollection(
		s,
		~makeShapeTable.(~endRate).as(Signal).asWavetable,
		1
	);
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		~eq = MultiEQ(2, \bhipass, 147.185, 0.dbamp, 0.504).play(chan);
	});
	out = /*MonoPorta*/Voicer(2, \distBass, args: [
		bufnum: ~shapeBuf.bufnum,
		freqRand: 1.0025, startRq: 1, endRq: 1, rqDecay: 1, freqlag: 0.08
	], target: ~target);
	// out.portaTime = 0.08;
	out.mapGlobal(\ffreq, nil, 261.4, \freq);
	out.mapGlobal(\fDecay, nil, 0.17, [0, 2, 3]);
	out.mapGlobal(\fegAmt, nil, 5, [0, 5]);
	// out.mapGlobal(\freqRand, nil, 1.0025, [1, 1.01, \exp]);
	// out.mapGlobal(\startRq, nil, 1, \myrq);
	// out.mapGlobal(\endRq, nil, 1, \myrq);
	// out.mapGlobal(\rqDecay, nil, 0, [0, 2, 3]);
	out.mapGlobal(\preamp, nil, 0.15, [0.1, 0.999, 2]);
	out
},
free: { ~target.free },
type: \vc) => Fact(\distbsVC);


