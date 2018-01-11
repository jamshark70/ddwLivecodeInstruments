{
	var n = 10;

	SynthDef(\fmHarm, { |out, gate = 1, fund = 50, freq = 440, freqlag = 0.08,
		cDetune = 1, mDetune = 1,
		cbuf, mbuf, index = 1, amp = 0.1, pan = 0,
		attack = 0.05, decay = 0.1, sus = 0.7, release = 0.12|
		// -1 because you actually get sidebands around the ratio:
		// if ratio == 6, you hear harmonics 5 and 7.
		// To make 7 the top pitch, subtract one.
		var ratio = Lag.kr((freq / fund).round(1) - 1, freqlag),
		mod = Osc.ar(mbuf, fund * ratio * mDetune * [1, cDetune], 0, index),
		car = Osc.ar(cbuf, fund * [1, cDetune] * (1 + mod), 0),
		eg = EnvGen.kr(Env.adsr(attack, decay, sus, release), gate, doneAction: 2);
		car = BRF.ar(Mix(car), fund, 1, amp);
		Out.ar(out, Pan2.ar(car, pan, eg));
	}).add;

	SynthDef(\fmHarms, { |out, gate = 1, t_gate = 1, fund = 50, freq = 440, freqlag = 0.08,
		// cDetune and mDetune are random limits
		cDetune = 1, mDetune = 1,
		cbuf, mbuf, index = 1, amp = 0.1, pan = 0,
		attack = 0.05, decay = 0.1, sus = 0.7, release = 0.12|
		// -1 because you actually get sidebands around the ratio:
		// if ratio == 6, you hear harmonics 5 and 7.
		// To make 7 the top pitch, subtract one.
		var cDetuneLow = cDetune.reciprocal, mDetuneLow = mDetune.reciprocal,
		cDetunes = Array.fill(n, { TExpRand.kr(cDetuneLow, cDetune, t_gate) }),
		mDetunes = Array.fill(n, { TExpRand.kr(mDetuneLow, mDetune, t_gate) }),
		ratio = Lag.kr((freq / fund).round(1) - 1, freqlag),
		mod = Osc.ar(mbuf, Lag.kr(fund * ratio * mDetunes * cDetunes, freqlag), 0, index),
		car = Osc.ar(cbuf, Lag.kr(fund * cDetune, freqlag) * (1 + mod), 0),
		eg = EnvGen.kr(Env.adsr(attack, decay, sus, release), gate, doneAction: 2);
		car = BRF.ar(Mix(car), fund, 1, amp);
		Out.ar(out, Pan2.ar(car, pan, eg));
	}).add;
}.value;

(
(
keys: #[master, shortrvbmc],
initLevel: -12.dbamp,
rvbLevel: -3.5.dbamp,
// hard-coding 3 octave drop: fix later
argPairs: [amp: 0.5],
postArgs: Pbind(
	\fund, Pfunc { |ev|
		var rootFreq, mode, octaveRatio;
		// doesn't check scale/tuning change
		if(~saveFundFreq.isNil or: { ~modeChanged ?? { false } }) {
			if(ev[\mode].notNil) {
				mode = ev[\mode].asMode;
				rootFreq = mode.cps(ev[\octave] * mode.scale.size);
				octaveRatio = mode.tuning.tryPerform(\octaveRatio) ?? { 2 };
			} {
				rootFreq = ev.copy.put(\degree, 0).use { ~detunedFreq.value };
				octaveRatio = ev[\tuning].tryPerform(\octaveRatio) ?? {
					ev[\scale].tryPerform(\octaveRatio) ?? { 2 }
				};
			};
			~saveFundFreq = rootFreq * (octaveRatio ** (-3));
			~modeChanged = false;
		};
		~saveFundFreq
	}
),
extraParms: (
	modeChanged: false,
	setDefaultHook: { |key, value|
		if(~modeKeys.includes(key)) { ~modeChanged = true };
	}
),
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		chan.newPostSend(~shortrvbmc, ~rvbLevel);
		// 2x 2nd-order = -24 dB/oct
		~eq = StaticEQ.new(2, \hipass, 201.16, 0.dbamp, 1, \hipass, 201.16, 0.dbamp, 1).play(chan);
	});
	~cbuf = Buffer.alloc(s, 1024, 1, completionMessage: { |buf| buf.sine1Msg(#[1]) });
	~mbuf = Buffer.alloc(s, 1024, 1, completionMessage: { |buf| buf.sine1Msg(#[1]) });

	out = /*MonoPorta*/Voicer(2, \fmHarms, [
		cbuf: ~cbuf.bufnum, mbuf: ~mbuf.bufnum,
		fund: 77.78,
	], target: ~target);
	out.mapGlobal(\index, nil, 3.86, [0.5, 10, \exp]);
	out.mapGlobal(\detun, nil, 1.008, \mydetune);
	out.setArgDefaults([
		\cDetune, out.globalControls[\detun].asMap,
		\mDetune, out.globalControls[\detun].asMap,
	]);
	out
},
free: { [~target, ~cbuf, ~mbuf].free },
type: \vc) => Fact(\fmMelVC);
);


/*
VC(\fmm).free;
/make(fmMelVC:fmm);
/make(melBP:m);
VC(\fmm) => BP(\m);
BP(\m).defaults.put(\fund, 24.midicps);

/m = "12345678";
/m+

/m = "\ins("", "*", 16, 0.25)::\ins(, "*", 3, 0.125)::\shuf(, "1~2~3~4~5~6~7~8~")";

/m => t

/m-
*/



// pulsey thing, kind of cheesy acidy but useful
(
SynthDef(\pulseLead, { |out, gate = 1, t_gate, amp = 0.1,
	freq = 440, i_prevFreq = -1,  // for initial pitch slide
	pwidth = 0.5, detun = 1.01, detunRand = 1.005, widthRand = 0.05, freqLag = 0.08, spread = 0.6,
	ffreq = 2000, gain = 1, t_panic = 0, ffDecay = 0.1, ffHeight = 0, acc = 0,
	atk = 0.01, dcy = 0.15, sus = 0.5, rel = 0.1, retrigLevel = 0.05|
	var n = 7,
	sig,
	// detuneArray = [detun.reciprocal, 1, detun],
	detuneArray = Array.fill(n, { |i| detun ** (i / (n-1) * 2 - 1) }),
	ffreqEg = EnvGen.kr(Env.perc(0.01, ffDecay), gate) * (ffHeight * (acc > 0)),
	egTest = LocalIn.kr(1, 0), eg,
	retrig = t_gate * (egTest < retrigLevel);  // at trig time, are we below retrigLevel?

	i_prevFreq = Select.kr(i_prevFreq < 0, [i_prevFreq, freq]);  // negative, don't slide
	freq = Select.kr(
		// moderately obscene workaround for
		// https://github.com/supercollider/supercollider/issues/2343
		// I have a UGen sketch that could help, but this is public code, so... ugly time
		Duty.kr(Dseq([ControlDur.ir, Dseq([1], inf)]), 0, Dseq([1, Dseq([0], inf)])),
		[freq, i_prevFreq]
	);
	freq = Lag.kr(freq, freqLag);

	sig = Pulse.ar(
		freq * detuneArray * Array.fill(detuneArray.size, {
			TExpRand.kr(detunRand.reciprocal, detunRand, t_gate)
		}),
		Clip.kr(pwidth + Array.fill(detuneArray.size, {
			TRand.kr(widthRand.neg, widthRand, t_gate)
		}), 0.01, 0.99)
	);
	sig = Splay.ar(sig.scramble, spread) * amp;

	ffreq = ffreq * (1 + ffreqEg);
	sig = MoogFF.ar(sig, Clip.kr(ffreq, 20, 20000), gain, t_panic);

	gate = (gate > 0) - (retrig > 0);
	eg = EnvGen.kr(Env.adsr(atk, dcy, sus, rel), gate, doneAction: 2);
	LocalOut.kr(eg);
	sig = sig * eg;

	Out.ar(out, sig);
}).add;

(
keys: #[master, shortrvbmc],
initLevel: -9.7.dbamp,
rvbLevel: -0.948.dbamp,
argPairs: [amp: 0.5],
make: { |name|
	var out;
	~target = MixerChannel(name, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
		chan.newPostSend(~shortrvbmc, ~rvbLevel);
	});

	out = Voicer(2, \pulseLead, target: ~target);
	// out.mapGlobal(\pwidth, nil, 0.5, [0, 1]);
	out.mapGlobal(\ffreq, nil, 1800, \freq);
	out.mapGlobal(\gain, nil, 1, [0, 3.999]);
	out.mapGlobal(\ffHeight, nil, 2, [0, 10]);
	out.mapGlobal(\detun, nil, 1.01, \mydetune);
	out
},
free: { ~target.free },
type: \vc) => Fact(\pulseLeadVC);
);