{ |... id|
	var spec;
	if(id.size > 0) {
		// collect, to post objects rather than keys
		id.collect { |id|
			var firstID = id.asArray[0];
			spec = Fact(\drumBP).available[firstID];
			Fact(\drumBP).chuck(BP(spec.tryPerform(\at, \bpname) ?? { firstID }), nil, (drumID: id));
		};
	} {
		"Please supply drum IDs as arguments".warn;
	};
} => Func(\drum);

(
keys: #[master, rvbmc, shortrvbmc],
dir: thisProcess.nowExecutingPath.dirname +/+ "samples",
autoGui: true,
available: (
	/** Kicks **/
	// Tight
	// Booming (Ferguson)
	deepkick: (
		bpname: \dk,
		// path: "deep_dance_kick_3.aif",
		path: "round_808_kick.aif",
		level: -10.04.dbamp, // -13.5, -9, -6.8.dbamp,
		rvbLevel: nil,
		fx: { |chan|
			~eq = MultiEQ(2,
				\bhipass, 67.401, 0.dbamp, 0.534,
				\eq, 149.762, -4.662.dbamp, 1.147,
				\eq, 4818.807, 8.271.dbamp, 0.983,
				\eq, 211.912, 4.361.dbamp, 1.0  // mid bump for mobile speakers
			).play(chan);
		},
		postDefaults: Plazy {
			Pbind(
				\time, min(
					BPStream(\maxTime, envir: ~drums[~drumID.indexOf(\deepkick)]),
					(Pkey(\dur) / Ptempo()) - 0.05
				),
				\decay, BPStream(\decay, envir: ~drums[~drumID.indexOf(\deepkick)])
			)
		},
		parmMap: (ampBuf: ($_: 0.4, $o: 0.75, $x: 1, $*: 0.75)),
		extras: (maxTime: 0.14, decay: 0.05)
	),
	tightkick: (
		bpname: \tk,
		path: "lovely-kick.aif",
		level: -7.9.dbamp, // -10.4, -4.6.dbamp, // -3.1.dbamp,
		rvbLevel: nil,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\eq, 382.329, -9.474.dbamp, 0.04,
				\eq, 139.718, -9.173.dbamp, 0.07,
				\eq, 197.699, -10.376.dbamp, 0.085,
				\eq, 439.277, -7.068.dbamp, 0.085,
				\eq, 569.907, -7.97.dbamp, 0.07,
				\bhipass, 56.662, 0.0.dbamp, 0.504,  // 0.668,  higher Q --> more sub
				\eq, 235.17, 4.962.dbamp, 1.0,
				\eq, 4121.927, 10.97.dbamp, 1.0  // +11 dB *very unusual* but this drum doesn't cut thru
			).play(chan);
		},
		parmMap: (ampBuf: ($_: 0.4, $o: 0.75, $x: 1, $*: 0.75)),
		postDefaults: (time: 0.15)
	),
	// Midrange
	midkick: (
		bpname: \mk,
		path: "phatbd.aif",
		level: -9.6.dbamp, // -7.dbamp,
		rvbLevel: nil,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\eq, 123.733, -8.271.dbamp, 0.16,
				\eq, 178.147, -7.368.dbamp, 0.085,
				\eq, 315.88, -7.368.dbamp, 0.07,
				\bhipass, 71.0, 0.0.dbamp, 0.414,
				\eq, 201.16, 5.564.dbamp, 0.833,
				\eq, 208.266, -8.571.dbamp, 0.1,
				\eq, 265.55, -7.97.dbamp, 0.085,
				\eq, 132.629, -6.466.dbamp, 0.698
			).play(chan);
		},
		parmMap: (ampBuf: ($_: 0.4, $o: 0.75, $x: 1, $*: 0.75)),
	),
	// Weirdo (some funky pitch countour at the start)
	/** Snares **/
	// Tight
	tightsnr: (
		bpname: \tsn,
		path: "606snar.aiff",
		level: -10.dbamp, // -7.9.dbamp, // -9.8.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -2.9.dbamp,
		pan: 0.3,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\eq, 201.16, -11.278.dbamp, 0.055,
				\eq, 270.199, -10.376.dbamp, 0.055
			).play(chan);
			~parmMap = ~parmMap.copy;
		},
		parmMap: (ampBuf: ($.: 0.3, $-: 0.75, $^: 1, $*: 0.75)),
	),
	// Fat
	fatsnr: (
		bpname: \fsn,
		path: "thick_hard_sd-eq.aif",
		level: -14.8.dbamp, // -11.2.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -2.8.dbamp,
		pan: 0.3,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\eq, 2324.645, -11.579.dbamp, 0.07
			).play(chan);
		},
		parmMap: (ampBuf: ($.: 0.4, $-: 0.75, $^: 1, $*: 0.75)),
	),
	// Quasi-pitched
	pitchsnr: (
		bpname: \psn,
		path: "metal-sd4.wav",
		level: -14.dbamp, // -8.dbamp, // -7.dbamp,
		rvbChan: \rvbmc,  // alt: \shortrvbmc
		rvbLevel: -1.dbamp,  // alt: -3.537.dbamp
		pan: 0.3,
		fx: { |chan|
			~event.instrument = \bufGrainPan2;
			~eq = MultiEQ.new(2,
				\hipass, 247.739, 0.dbamp, 1,
				\eq, 243.477, -9.774.dbamp, 0.055,
				\eq, 327.038, -9.173.dbamp, 0.055,
				\eq, 395.833, -12.481.dbamp, 0.145,
				\eq, 513.544, -8.571.dbamp, 0.055,
				\eq, 689.792, -9.474.dbamp, 0.055,
				\eq, 879.521, -10.075.dbamp, 0.055,
				\eq, 1181.372, -10.075.dbamp, 0.055
			).play(chan);
		},
		parmMap: (ampBuf: ($.: 0.4, $-: 0.75, $^: 1, $*: 0.75)),
	),
	// Clap
	clap: (
		bpname: \clp,
		path: "Clap01.aiff",
		level: -12.9.dbamp, // -8.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -6.6.dbamp,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\hipass, 239.287, 0.dbamp, 1
			).play(chan);
		},
		parmMap: (ampBuf: ($.: 0.4, $-: 0.75, $^: 1, $*: 0.75)),
	),
	// Realistic (maybe steal 80s-style from "Wiggle Room"?)
	snr80: (
		bpname: \s8,
		path: "SNARE1.aif",
		level: -14.8.dbamp, // -8.6.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -2.dbamp,
		pan: 0.3,
		fx: { |chan|
			~eq = MultiEQ.new(2,
				\eq, 183.174, -8.271.dbamp, 0.24,
				\eq, 9319.051, 3.459.dbamp, 0.878,
				\eq, 389.022, -4.06.dbamp, 1.252
			).play(chan);
		},
		parmMap: (ampBuf: ($.: 0.4, $-: 0.75, $^: 1, $*: 0.75)),
	),
),
// availStart: (snare: 0, kick: 0),  // unused?
drumID: \fatsnr,
initLevel: 3.dbamp,  // no volume change from process master channel's panner
rvbLevel: 0.dbamp,
make: { |name|
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \singleSynthPlayer),
		dir: ~dir,
		drumID: ~drumID,
		available: ~available,
		initLevel: ~initLevel,
		rvbLevel: ~rvbLevel,
		master: ~master,
		rvbmc: ~rvbmc,
		shortrvbmc: ~shortrvbmc,
		autoGui: ~autoGui,
		userprep: {
			~drumID = ~drumID.asArray.select { |key|
				if(~available[key].isNil) {
					"BP(%): Drum ID % is not known.".format(
						~collIndex.asCompileString, ~drumID.asCompileString
					).warn;
					false
				} { true };
			};
			if(~drumID.size == 0) {
				Error("drumsetBP: Please supply the names of existing BPs").throw;
			};
			if(~drumID.size > 1) {
				~bpsubmix = MixerChannel(~collIndex, s, 2, 2, ~initLevel, ~pan ? 0, outbus: ~master);
				~inChannels = ~bpsubmix.inChannels;
				~outChannels = ~bpsubmix.outChannels;
			} {
				~inChannels = 2;
				~outChannels = 2;
			};
			~loadDrums.();
			// for GUI
			if(~drums.size > 1) {
				~chan = ~bpsubmix
			} {
				~chan = ~drums[0].chan
			};
			// version safety: new instruments + old cll won't know how to do this
			if(~autoGui == true and: { PR(\clMake).v[\autoAssignMixer].notNil }) {
				PR(\clMake).autoAssignMixer(~chan);
			};
		},
		userfree: {
			~drums.do { |thing| thing[\buf].free; thing[\chan].free };
			~bpsubmix.free;
		},
		defaultParm: \ampBuf,
		parmMap: (),
		instrMap: (1: \bufGrainPan, 2: \bufGrainPan2),  // numChannels -> synthdef name
		commonParams: Plazy {
			Pbind(
				\bufnum, Pswitch1(~drums.collect(_.buf), Pkey(\bufIndex)),
				\chan, Pswitch1(~drums.collect(_.chan), Pkey(\bufIndex)),
				// drums' postDefaults may override these
				\start, Pswitch1(~drums.collect(_.start), Pkey(\bufIndex)),
				\time, Pswitch1(~drums.collect(_.time), Pkey(\bufIndex)),
				\instrument, Pdict(
					~instrMap,
					Pfunc { |ev| ev[\bufnum].numChannels },
					inf
				)
			)
		},
		postDefaults: Prout { |inEvent|
			var bufIndex, event, postDefaults, delta, indices;
			~drumSelector = Pswitch1(
				~drums.collect { |thing| thing[\postDefaults] ?? { Pbind.new } },
				Pkey(\bufIndex)
			).asStream;
			~makeStreamForKey.(\commonParams);
			loop {
				if(inEvent[\bufIndex].size == 0) {
					inEvent = ~commonParamsStream.next(inEvent);
					inEvent = ~drumSelector.next(inEvent).yield;
				} {
					delta = inEvent.delta;
					inEvent[\bufIndex].do { |bufIndex, i|
						event = inEvent.copy
						.put(\bufIndex, bufIndex);
						event.keysValuesDo { |key, value|
							if(~shouldNotIndexPerDrum.(key).not) {
								event.put(key, value.wrapAt(i));
							};
						};
						event = ~commonParamsStream.next(event);
						event = ~drumSelector.next(event);
						if(i < (inEvent[\bufIndex].size - 1)) {
							event.put(\delta, 0).play;
						} {
							inEvent = event.yield;
						};
					}
				}
			}
		},
		// drumThing: (buf, channel, defaults, postDefaults...)
		loadDrums: {
			var parmMap = IdentityDictionary.new,
			volAdjust = if(~drumID.size > 1) { 3.dbamp } { 1 },
			path;
			~drums = ~drumID.collect { |key, i|
				var thing = ~available[key],
				chan = MixerChannel((~collIndex ++ key).asSymbol, s,
					~inChannels, ~outChannels,
					thing[\level] * volAdjust, thing[\pan] ? 0,
					outbus: ~bpsubmix ?? { ~master }, completionFunc: { |chan|
						thing[\fx].value(chan);
						if(thing[\rvbLevel].notNil) {
							chan.newPostSend(
								(thing[\rvbChan] ?? { \rvbmc }).envirGet,
								thing[\rvbLevel] / volAdjust
							);
						};
					}
				), out;
				~addThingToParmMap.(thing, i);
				if(PathName(thing[\path]).isAbsolutePath) {
					path = thing[\path];
				} {
					path = ~dir +/+ thing[\path];
				};
				out = (
					buf: Buffer.readAndQuery(s, path, thing[\start] ? 0,
						completionFunc: inEnvir { |buf| ~drums[i][\time] = buf.duration }),
					chan: chan,
					start: thing[\start] ? 0,
					postDefaults: thing[\postDefaults],
				);
				if(thing[\extras].isKindOf(Dictionary)) { out.putAll(thing[\extras]) };
				out
			};
			~parmMap.keysValuesDo { |parm, map|
				map.keysValuesDo { |event, values|
					if(~shouldNotIndexPerDrum.(parm, event, map).not) {
						if(values.size > 1) {
							map[event] = values.flop;
						} {
							map[event] = values.flatten(1);
						};
					};
				};
			};
			~drums
		},
		addThingToParmMap: { |thing, i|
			thing[\parmMap].keysValuesDo { |parm, map|
				var localParm;
				if(~parmMap[parm].isNil) {
					~parmMap[parm] = IdentityDictionary.new;
					if(parm == ~defaultParm) {
						~parmMap[parm][\alias] = [\amp, \bufIndex]
					} {
						~parmMap[parm][\alias] = [\amp]
					};
				};
				localParm = ~parmMap[parm].put(\fromDrum, true);
				map.keysValuesDo { |event, value|
					if(~shouldNotIndexPerDrum.(parm, event, localParm)) {
						localParm[event] = value;
					} {
						if(localParm[event].isNil) {
							localParm[event] = [[value, i]]
						} {
							localParm[event] = localParm[event].add([value, i]);
						};
					};
				};
			};
		},
		shouldNotIndexPerDrum: { |parm, event, map(~parmMap[parm])|
			(map.tryPerform(\at, \fromDrum) ?? { false }).not or: { ~reservedKeys.includes(event) }
		},
		reservedKeys: #[isPitch, alias, fromDrum]
	));
	TempoClock.default => BP(name);
}, type: \bp) => Fact(\drumBP);


/** Hats **/
(
keys: #[master, shortrvbmc],
dir: thisProcess.nowExecutingPath.dirname +/+ "samples",
autoGui: true,
available: (
	// Tight, thin
	thinhh: (
		bpname: \thh,
		paths: #[
			"chh808.aif",
			"ohh808b.aif"
		],
		bufStart: #[1810, 0],
		level: -21.34.dbamp, // -16.3.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -7.4.dbamp,
		pan: -0.3,
		// fx: { |chan|
		// 	MultiEQ(2,
		// 	).play(chan);
		// },
		// postDefaults: {
		// 	Pbind(
		// 		\time, min(BPStream(\maxTime), (Pkey(\dur) / Ptempo()) - 0.05),
		// 		\decay, BPStream(\decay)
		// 	)
		// },
		// extras: (maxTime: 0.25, decay: 0.05)
	),
	// More rich, longer open-hat
	thickhh: (
		bpname: \hh,
		paths: #[
			"chh.aif",
			"smallohh.aif"
		],
		bufStart: #[675, 0],
		level: -24.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -7.3.dbamp,
		pan: -0.3,
		fx: { |chan|
			~eq = MultiEQ(2,
				\eq, 9001.115, 3.dbamp, 1,
				\eq, 910.587, -9.774.dbamp, 0.055,
				\eq, 1266.303, -10.075.dbamp, 0.055
			).play(chan);
		}
	),
	// Synthetic
	synthhh: (
		bpname: \shh,
		paths: #[
			"606mhat.aiff",
			"606ohat.aiff"
		],
		bufStart: #[0, 0],
		level: -27.3.dbamp, // -22.5.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -5.9.dbamp,
		pan: -0.3,
		fx: { |chan|
			~eq = MultiEQ(2,
				\eq, 3232.754, -3.459.dbamp, 0.055,
				\eq, 6038.506, -5.263.dbamp, 0.055,
				\eq, 7436.726, -6.767.dbamp, 0.055
			).play(chan);
		},
		// postDefaults: {
		// 	Pbind(
		// 		\time, min(BPStream(\maxTime), (Pkey(\dur) / Ptempo()) - 0.05),
		// 		\decay, BPStream(\decay)
		// 	)
		// },
		// extras: (maxTime: 0.25, decay: 0.05)
	),
	// Hard, staccato
	hardhh: (
		bpname: \hhh,
		paths: #[
			"glasscut-hat.aif",
			"cuts-through-it-ohh.aif"
		],
		bufStart: #[0, 0],
		level: -18.dbamp, // -31.6.dbamp, // -28.2.dbamp,
		rvbChan: \shortrvbmc,
		rvbLevel: -12.8.dbamp,
		pan: -0.3,
		fx: { |chan|
			fork {
				~shapeBuf = Buffer.alloc(s, 2048, 1, completionMessage: { |buf|
					buf.sine1Msg(#[1, 0, 1]);
				});
				s.sync;
				~shaper = chan.playfx({ |outbus| Shaper.ar(~shapeBuf, In.ar(outbus, 2).clip(-1, 1)) });
			};
			~userfree = ~userfree.addFunc { ~shapeBuf.free };
			// MultiEQ(2,
			// ).play(chan);
		},
		postDefaults: {
			Pbind(
				\time, min(BPStream(\maxTime), Pkey(\time)),
				\instrument, Pindex(#[bufGrainPan, bufGrainPan2], Pkey(\bufIndex)),
				\amp, BPStream(\amp)
			)
		},
		extras: (maxTime: 0.1, amp: 0.03)
	),
	// Metallic-buzzy
	// Realistic?
),
make: { |name|
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \singleSynthPlayer, instrument: \bufGrainPan),
		dir: ~dir,
		drumID: ~drumID,
		available: ~available,
		initLevel: ~initLevel,
		rvbLevel: ~rvbLevel,
		master: ~master,
		rvbmc: ~rvbmc,
		shortrvbmc: ~shortrvbmc,
		autoGui: ~autoGui,
		userprep: {
			var thing = ~available[~drumID], bufStart;
			if(thing.isNil) {
				Error("BP(%): Drum ID % is not known.".format(
					~collIndex.asCompileString, ~drumID.asCompileString
				)).throw;
			};
			~chan = MixerChannel(~collIndex, s, 2, 2, thing[\level], thing[\pan] ? 0,
				outbus: ~master, completionFunc: { |chan|
					thing[\fx].value(chan);
					if(thing[\rvbLevel].notNil) {
						chan.newPostSend((thing[\rvbChan] ?? { \rvbmc }).envirGet, thing[\rvbLevel]);
					};
				}
			);
			~event[\chan] = ~chan;
			bufStart = thing[\bufStart] ?? { #[0] };
			~bufs = thing[\paths].collect { |path, i|
				if(PathName(path).isRelativePath) {
					path = ~dir +/+ path;
				};
				Buffer.readAndQuery(s, path, bufStart.wrapAt(i));
			};
			// wrap drum-specific defaults around the process defaults
			#[defaults, postDefaults].do { |key|
				if(thing[key].notNil) {
					key.envirPut(Pchain(thing[key].value, key.envirGet));
				};
			};
			if(thing[\extras].notNil) {
				thing[\extras].keysValuesDo { |key, value|
					key.envirPut(value);
				};
			};
			if(~autoGui == true and: { PR(\clMake).v[\autoAssignMixer].notNil }) {
				PR(\clMake).autoAssignMixer(~chan);
			};
		},
		userfree: { [~chan, ~bufs].free },
		defaultParm: \bufIndex,
		parmMap: (
			bufIndex: ($x: 0, $o: 1, $.: 0, $-: 1)
		),
		postDefaults: Plazy {
			Pbind(
				#[bufnum, time], Pkey(\bufIndex).collect { |i, event|
					[~bufs[i], min(event.delta / thisThread.clock.tempo, ~bufs[i].duration)]
				}
			)
		},
	));
	TempoClock.default => BP(name);
}, type: \bp) => Fact(\hhBP);

{ |prevItem| if("-o".includes(prevItem)) { $. } { ".-".wchoose(#[0.7, 0.3]) } } => Func(\hhRand);

{ |... id|
	var spec;
	if(id.size > 0) {
		id.collect { |id|
			spec = Fact(\hhBP).available[id];
			Fact(\hhBP).chuck(BP(spec.tryPerform(\at, \bpname) ?? { id }), nil, (drumID: id));
		};
	} {
		"Please supply drum IDs as arguments".warn;
	};
} => Func(\hh);

// /make(break:b(path:"...",gridOffset:n,gridSamples:o,clips:(...)));
(
PR(\abstractLiveCode).copy.putAll((
	event: (eventKey: \singleSynthPlayer),
	userprep: {
		~chan = MixerChannel(~collIndex, s, 2, 2, ~initLevel, outbus: ~master, completionFunc: { |chan|
			chan.newPostSend(~rvbmc, ~rvbLevel);
			~fx.eval;
		});
		~event[\chan] = ~chan;
		~buf = Buffer.readAndQuery(s, ~path, completionFunc: inEnvir { |buf|
			// currentEnvironment.postln;
			~loopTempo = ~getLoopTempo.(buf.sampleRate);
			~bufFrames = ~buf.numFrames;
			~defaults.put(\instrument,
				switch(~buf.numChannels)
				{ 1 } { \bufGrainPan }
				{ 2 } { \bufGrainPan2 }
			);
		});
		~defaults[\bufnum] = ~buf.bufnum;
		~clips = ~clips.collect { |indices|
			~gridOffset + ((~gridSamples * ~clipDur) * indices)
		};
	},
	userfree: {
		[~chan, ~buf].free;
	},
	defaultParm: \clip,
	parmMap: (
		clip: (
			alias: #[start, rateMul],
			convertFunc: { |key|
				if(key.isKindOf(Char)) {
					if(~clips[key].notNil) {
						if(key.isUpper) {
							[~clips[key], 2]
						} {
							[~clips[key], 1]
						}
					} {
						[Rest(0), 1]
					}
				} {
					nil
				}
			}
		)
	),
	time: Pkey(\dur) / Ptempo() - Pkey(\attack) - Pkey(\decay),
	// decay is needed to avoid loose attacks at the end of a clip
	defaults: (attack: 0.001, decay: 0.045, rateMul: 1),
	postDefaults: Pbind(
		\rate, Ptempo() / BPStream(\loopTempo) * Pkey(\rateMul),
		\time, BPStream(\time),
		// try to find one of the clip options that can play thru to the next event
		// if not, use the earliest (because it will have the most audio data after it)
		\start, Pfunc { |ev|
			var samples = ev[\time] * ~buf.sampleRate * ev[\rate].abs,
			valid = ev[\start].select { |a| (~bufFrames - a) >= samples },
			out = if(valid.size > 0) {
				valid.choose
			} {
				ev[\start].minItem
			};
			// if reversing, start at the end
			if(ev[\rate] > 0) { out } { out + samples };
		}
	)
)) => PR(\clBreak);

PR(\clBreak).clone {
	~parmMap = ~parmMap.copy;
	~parmMap[\clip] = ~parmMap[\clip].copy.put(\convertFunc, { |key|
		if(key.isKindOf(Char)) {
			if(~clips[key].notNil) {
				if(key.isUpper) {
					[~clips[key], -1]
				} {
					[~clips[key], 1]
				}
			} {
				[Rest(0), 1]
			}
		} {
			nil
		}
	});
} => PR(\clRevBreak);

(
keys: #[master, shortrvbmc],
initLevel: -12.dbamp,
rvbLevel: -6.dbamp,
path: nil,
gridOffset: 0, // 588,
gridSamples: 30000, // 58166*0.5,
clipDur: 0.25,
clips: (
	$k:#[0, 2, 8],  // 16th-note indices, etc.
),
getLoopTempo: { |sr| sr / ~gridSamples },
fx: nil,  // symbol --> Func(...)
pr: \clBreak,
make: { |name|
	if(~path.isNil) {
		Error("Fact(\\breakBP) => BP(%): Must specify path, gridSamples, clips".format(name)).throw;
	};
	BP(name).free;
	PR(~pr).chuck(BP(name), nil, (
		initLevel: ~initLevel,
		rvbLevel: ~rvbLevel,
		master: ~master,
		rvbmc: ~shortrvbmc,
		path: ~path,
		gridOffset: ~gridOffset,
		gridSamples: ~gridSamples,
		clipDur: ~clipDur,
		clips: ~clips,
		getLoopTempo: ~getLoopTempo,
		fx: ~fx
	));
},
type: \bp) => Fact(\breakBP);
);
