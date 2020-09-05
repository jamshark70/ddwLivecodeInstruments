
(
(
keys: #[master, rvbmc],
initLevel: -12.dbamp,
rvbLevel: -6.dbamp,
// set: \tink,
dir: thisProcess.nowExecutingPath.dirname +/+ "samples/oddhits",
make: { |name|
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \singleSynthPlayer),
		initLevel: ~initLevel,
		rvbLevel: ~rvbLevel,
		master: ~master,
		rvbmc: ~rvbmc,
		set: ~set,
		sets: ~sets,
		database: ~database,
		dir: ~dir,
		// legacy, you *can* set these for more advanced overrides, but it's harder
		bufPaths: ~bufPaths,
		bufRates: ~bufRates,
		instrOverrides: ~instrOverrides,
		instrParms: ~instrParms,
		longChars: ~longChars,
		staccChars: ~staccChars,
		userprep: {
			if(~set.notNil) {
				~getParmsFromDatabase.(~set);
			} {
				Error("BP(%): (set: \\name) missing, one of %".format(
					~collIndex.asCompileString,
					~sets.keys.as(Array).sort
				)).throw;
			};
			~chan = MixerChannel(~collIndex, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
				chan.newPostSend(~rvbmc, ~rvbLevel);
			});
			~event[\chan] = ~chan;
			~fileInfo = ~checkFiles.(~bufPaths);
			~bufs = ~fileInfo.collect { |info|
				if(info[\numChannels] == 1) {
					Buffer.read(s, info.path)
				} {
					Buffer.readChannel(s, info.path, channels: #[0])
				}
			};
			~parmMap[\buf] = IdentityDictionary.new.put(\alias, #[bufIndex, stacc]);
			min(~bufs.size, ~longChars.size).do { |i|
				~parmMap[\buf][~longChars[i]] = [i, 0];
				~parmMap[\buf][~staccChars[i]] = [i, 1];
			};
			~instrParms = ~instrParms.extend(~bufs.size).collect { |x|
				if(x.isNil) { Pfunc { |ev| ev } } { x }
			};
		},
		userfree: {
			[~chan, ~bufs].free;
		},
		defaultParm: \buf,
		parmMap: (
			xpose: (
				isPitch: true,
				convertFunc: { |note, ev|
					var mode;
					if(note.isRest.not and: { note.isKindOf(SequenceNote) and: { ev.isRest.not } }) {
						mode = ev[\mode].asMode;
						// note: not supporting JI here
						// to do that, BP's mode should be its own copy of the mode object
						// that's too much to import, so ET it is
						mode.cps(note.asFloat, ev[\scAccidentals]) / mode.cps(0)
					} {
						1
					}
				}
			)
		),
		// You'd think xpose should be a SequenceNote (for convertFunc)
		// but there are two cases:
		// 1. There's an xpose pattern: default is not used (overridden).
		// 2. There's no xpose pattern -- convertFunc never runs, so
		// the item in ~defaults should be the real value.
		defaults: (adjust: 0, xpose: 1, scAccidentals: true),
		amp: 0.5,
		postDefaults: Plazy {
			// this is fairly ridiculous. I want to be able to swap in new parm patterns.
			// incredibly, the pattern system has no facility for this. So I have to watch
			// for any changes in the array. That means making a wholly redundant copy of
			// the array AND maintaining an array of streams.
			~saveInstrParms = ~instrParms.copy;
			~instrParmStreams = ~instrParms.collect(_.asStream);
			Pchain(
				// incredibly pointless hack follows
				Pfunc { |ev|
					var i = ev[\bufIndex];
					if(~instrParms[i] !== ~saveInstrParms[i]) {
						~saveInstrParms[i] = ~instrParms[i];
						~instrParmStreams[i] = ~instrParms[i].asStream;
					};
					~instrParmStreams[i].next(ev) ?? { ev }
				},
				Pbind(
					\instrument, Pfunc { |ev| ~fileInfo[ev[\bufIndex]][\instrument] },
					\bufnum, Pindex(~bufs, Pkey(\bufIndex)),
					\amp, BPStream(\amp) / Pfunc { |ev| ~fileInfo[ev[\bufIndex]][\peak] },
					// \rate, Pindex(~fileInfo.collect(_[\rate]), Pkey(\bufIndex)),
					\rate, Pfunc { |ev|
						~fileInfo[ev[\bufIndex]][\rate] * ev[\xpose].asFloat
					},
					\time, Pfunc { |ev|
						if(ev[\time].isNil) {
							if(ev[\stacc].notNil and: { ev[\stacc] > 0 }) {
								0.15 / thisThread.clock.tempo
							} {
								~fileInfo[ev[\bufIndex]][\numFrames] / ~bufs[ev[\bufIndex]].sampleRate
								/ ev[\rate]
							};
						} { ev[\time] }
					},
					// \adjust in seconds, \timingOffset in beats
					\timingOffset, Pkey(\timingOffset) + (Pkey(\adjust) * Ptempo())
				)
			)
		},
		getParmsFromDatabase: { |id|
			var indices = ~sets[id], thing;
			if(indices.isNil) {
				Error("BP(%): Unknown fileset %".format(id.asCompileString)).throw;
			} {
				~bufPaths = Array(indices.size);
				~bufRates = Array(indices.size);
				~instrOverrides = Array(indices.size);
				~instrParms = Array(indices.size);
				indices.do { |i|
					thing = ~database[i];
					if(thing.isKindOf(Association)) {
						~bufPaths.add(~dir +/+ thing.key);
						~bufRates.add(thing.value[\rate] ?? { 1 });
						~instrOverrides.add(thing.value[\instr]);  // nil ok as fallback
						~instrParms.add(thing.value[\parms]);
						thing.value[\prepareBP].(BP(~collIndex));  // no-op if nil
					} {
						~bufPaths.add(~dir +/+ thing);
						~bufRates.add(1);
						~instrOverrides.add(nil);
						~instrParms.add(nil);
					}
				}
			}
		},
		checkFiles: { |paths|
			var info = Array.new(paths.size);
			paths.collect { |path, i|
				var sf = SoundFile.openRead(path);
				if(sf.notNil) {
					info.add((
						path: path,
						numFrames: sf.numFrames,
						numChannels: sf.numChannels,
						peak: sf.channelPeaks(threaded: false)[0],  // eventually read only channel 0
						// must store here b/c we might not load all files
						rate: ~bufRates.wrapAt(i),
						instrument: ~instrOverrides.wrapAt(i) ?? { \bufGrainPan }
					));
				} {
					"BP(%) could not read '%'".format(~collIndex.asCompileString, path).warn;
				};
			};
			info
		},
		instrParmsAt: { |char|
			var i = ~parmMap[~defaultParm][char];
			if(i.notNil) { ~instrParms[i[0]] };
		}
	));
},
sets: (machine: #[0, 1, 2], tink: #[3, 4], whistle: #[5, 6, 7], wiggle: #[8, 9, 10]),
database: [
	"motorfunk.aif" -> (
		parms: PbindProxy(\adjust, -5381/44100).quant_(0),
		prepareBP: { |bp| bp.leadTime = 0.1 }
	),
	"spinz.aiff",
	"energy-charge-squeal.aif" -> (
		instr: \bufGrainFilt,
		parms: PbindProxy(
			\ffreq, 4540, // Pexprand(1000, 6000, inf),
			\time, 0.143492, \decay, 0.034
		).quant_(0)
	),

	"thinsyn.wav",
	"pip.aif",

	"alarmblop.wav",
	"electrodroplet.wav" -> (parms: PbindProxy(\amp, Pkey(\amp) * 0.5, \rate, 1.7.midiratio).quant_(0)),
	"hiphopwhstl.wav" -> (parms: PbindProxy(\amp, Pkey(\amp) * 0.5).quant_(0)),

	"doubleshot.aif" -> (
		parms: PbindProxy(\amp, -6.dbamp).quant_(0)
	),
	"thinsyn.wav" -> (rate: 1.6),
	"electronic_wiggle.wav" -> (
		parms: PbindProxy(\amp, -14.dbamp).quant_(0)
	),
],
longChars: "_-^",
staccChars: ",.!",

type: \bp) => Fact(\bufBP);
);

(
SynthDef(\bufGrainFilt, { |start, time, bufnum, pan, rate = 1, amp = 1,
		attack = 0.001, decay = 0.02, ffreq = 2000, rq = 1, outbus|
	var sig;
	sig = PlayBuf.ar(1, bufnum, rate * BufRateScale.kr(bufnum), 1, start, 0)
		* EnvGen.kr(Env.linen(attack, time, decay), doneAction:2);
	sig = BLowPass/*RLPF*/.ar(sig, ffreq, rq);
	Out.ar(outbus, Pan2.ar(sig, pan, amp));
}).add;
);

// synth kick

(
SynthDef(\sinkik, { |out, basefreq = 50, preamp = 7.724, amp = 0.322,
	topRatio = 10, dcy = 0.0685,
	atk = 0.005, dcy1 = 0.04, dcy2 = 0.0972, rel = 0.05,
	retrigFreq = 0, time = 1|
	var trig = Impulse.ar(retrigFreq) * (Sweep.ar < time),
	freq = basefreq * EnvGen.ar(
		Env([topRatio, topRatio, 1], [0.002, dcy], -4),
		trig
	),
	sig = (SinOsc.ar(freq) * preamp.dbamp).tanh * amp,
	eg = EnvGen.ar(Env([0, 1, 0.6, 0.4, 0], [atk, dcy1, dcy2, rel], -4), trig, doneAction: 2);
	Out.ar(out, sig * eg);
}).add;

(
defaultName: \sk,
keys: #[master, rvbmc],
initLevel: -18.5.dbamp,
rvbLevel: -6.dbamp,
basefreq: 50,
make: { |name|
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \singleSynthPlayer),
		initLevel: ~initLevel,
		master: ~master,
		userprep: {
			~chan = MixerChannel(~collIndex, s, 1, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
				~eq = MultiEQ(1,
					\bhipass, 57.654, 0.0.dbamp, 0.444,
					\eq, 67.401, 3.158.dbamp, 0.728,
					\eq, 299.854, -4.361.dbamp, 1.0
				).play(chan);
			});
			~event.put(\chan, ~chan);
			~preampCtl = GenericGlobalControl(\preamp, nil, 7.724, [0, 40]);
			~defaults.put(\preamp, ~preampCtl.asMap);
			~globalControls = [~preampCtl];  // publish for mobile interface
		},
		userfree: {
			[~chan, ~preampCtl].free;
		},
		defaultParm: \ampPair,
		parmMap: (ampPair: (
			alias: #[amp, dcy2],
			// 0.04 distinguishes for rolls -- a bit hacky but we only have the data, not the key, in the event
			$o: [0.75, 0.0972], $_: [0.3, 0.0972], $=: [0.3, 0.04]
		)),
		defaults: (instrument: \sinkik, basefreq: ~basefreq),
		retrigFreq: 12,  // 12 notes per beat
		postDefaults: Pbind(
			// must be above \dcy2 below
			\retrigFreq, Pif(
				Pbinop('==', Pkey(\dcy2), 0.04),
				BPStream(\retrigFreq) * TempoClock.tempo,
				0  // normal case, 0 suppresses roll
			),
			\sustain, Pkey(\dur) * 0.9,
			\dcy2, min(Pkey(\dcy2), Pkey(\sustain) / Ptempo()),
			\time, Pkey(\sustain) / Ptempo()
		)
	));
},
type: \bp) => Fact(\sinkikBP);
);

// rollable 606 snare
(
(
defaultName: \sdr,
keys: #[master, shortrvbmc],
initLevel: -11.6.dbamp, // -7.5.dbamp,
rvbLevel: -3.8.dbamp,
drumKey: \tightsnr,  // don't delete -- pulls the parmMap from drumBP
make: { |name|
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \singleSynthPlayer),
		initLevel: ~initLevel,
		rvbLevel: ~rvbLevel,
		master: ~master,
		rvbmc: ~shortrvbmc,
		drumKey: ~drumKey,
		userprep: {
			var spec = Fact(\drumBP).available[~drumKey];
			if(spec.isNil) {
				Error("sdrollBP: Invalid drumKey %".format(~drumKey.asCompileString)).throw;
			};
			~chan = MixerChannel(~collIndex, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
				chan.newPostSend(~rvbmc, ~rvbLevel);
				spec[\fx].value(chan);
			});
			~buf = Buffer.readChannel(s, "/home/dlm/share/SC/downloaded-quarks/ddwLivecodeInstruments/samples/606snar.aiff", channels: #[0]);
			~event.put(\chan, ~chan);
			~defaults.put(\bufnum, ~buf);
			spec[\parmMap].keysValuesDo { |key, map|
				if(key == \ampBuf) {
					map = map.collect { |item| [item, \bufGrainPan] };  // returns new dict
					map.put($=, [1, \bufRollPanChangeRate]).put(\alias, #[amp, instrument]);
					key = \ampPair;
				};
				~parmMap.put(key, map);
			};
		},
		userfree: {
			[~chan, ~buf].free;
		},
		defaultParm: \ampPair,
		parmMap: (),
		defaults: (),
		postDefaults: Psym1(Pkey(\instrument), (
			bufGrainPan: Pbind(\time, Pfunc { ~buf.duration }),
			bufRollPanChangeRate: Pbind(
				\strokeRateStart, 32,
				\strokeRateEnd, 7,
				\time, max(Pkey(\dur) * 0.8, Pkey(\dur) - 0.1) / Ptempo()
			)
		))
	));
},
type: \bp) => Fact(\sdrollBP);
);
