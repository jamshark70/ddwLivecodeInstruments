// some reusable pitch-playing processes

// if true: chord/arpegBP factories prefer mode stored in MIDIRecBuf properties
// if false: chord/arpegBP factories prefer \default mode
if(Library.at(\clUseBufMode).isNil) {
	Library.put(\clUseBufMode, false);
};

// defaults handling is quite complex
// proc events can be an event or a pattern
// voicer argPairs can override
// then, setDefaults can override the override
(
Proto {
	~noop = Pfunc { |ev| ev };
	~prep = { |base, bpKey|
		// BP(bpKey) may not exist yet
		~base = if(base.isPattern and: { BP.exists(bpKey) }) {
			Plazy {
				Penvir(BP(bpKey).v, base, false)  // not independent, use real BP environment
			}
		} {
			base
		};
		~voicerOverride = ~noop;
		~override = PbindProxy.new.quant_(0);
		~voicerPostArgs = ~noop;
		~bpKey = bpKey;
		currentEnvironment
	};
	~setDefault = { |key, value|
		~override.set(key, value);
		~setDefaultHook.(key, value);
		currentEnvironment
	};
	~setVoicerParms = { |parms, post|
		case
		{ parms.isNil } {
			parms = ~noop;
			~setDefaultHook.();  // should handle nil
		}
		{ parms.isKindOf(SequenceableCollection) } {
			parms.pairsDo { |key, value| ~setDefaultHook.(key, value); };
			parms = Pbind(*parms);
		};
		case
		{ post.isNil } {
			post = ~noop;
			~setDefaultHook.();  // should handle nil
		}
		{ post.isKindOf(SequenceableCollection) } {
			post.pairsDo { |key, value| ~setDefaultHook.(key, value); };
			post = Pbind(*post);
		};
		if(BP.exists(~bpKey)) {
			parms = Penvir(BP(~bpKey).v, parms, false);  // not independent, use real BP environment
			post = Penvir(BP(~bpKey).v, post, false);
		};
		~voicerOverride = parms;
		~voicerPostArgs = post;
		currentEnvironment
	};
	~setDefaultHook = { |key, value|
		if(BP.exists(~bpKey)) {
			BP(~bpKey).v.tryPerform(\setDefaultHook, key, value);
		};
	};
	~asPattern = {
		Pchain(
			BPStream(\voicerPostArgs),
			BPStream(\override),
			BPStream(\voicerOverride),
			BPStream(\base)
		)
	};
	~asStream = { ~asPattern.().asStream };  // for BPStream, in parent
} => PR(\clDefaults);
);

// basic melody
(
bassID: nil,
mode: \default,
octave: 5,
leadTime: 0,
make: { |name|
	var leadTime = ~leadTime;
	BP(name).free;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \default, type: \voicerArtic),
		bassID: ~bassID,
		defaultParm: \degree,
		parmMap: (
			degree: (isPitch: true),
			acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/)
		),
		defaults: PR(\clDefaults).copy.prep((
			mode: ~mode ?? { \default },
			octave: ~octave ?? { 5 }
		), name),
		postDefaults: Pchain(
			Plazy { BPStream(\voicerPostArgs, envir: ~defaults) },
			BPStream(\userPost),
			Pfunc { |ev|
				var mode, bassID;
				if(ev.isRest.not) {
					mode = ev[\mode].asMode;
					ev[\freq] = mode.cps(ev[\degree] + (ev[\octave] * mode.scale.size));
					if(~bassID.notNil) {
						Library.put(~bassID, ev[\degree] % mode.scale.size);
						bassID = ~bassID;
						thisThread.clock.sched(0, { BP.changed(bassID, ev) });
					};
					if(ev[\accent].isNil) {
						ev[\accent] = ev[\acc].notNil and: { ev[\acc] > 0 };
					};
					ev[\acc] = ev[\accent].asInteger;  // synchronize accent from note vs sub-parameter
				};
				ev
			}
		),
		userPost: Pfunc { |ev| ev },
		bindVC: Func(\bindVC).v,
		modeKeys: #[mode, root, scale, tuning, octave],
		setDefault: { |key, value| ~defaults.setDefault(key, value) },
		setVoicerParms: { |parms, post| ~defaults.setVoicerParms(parms, post) }
	));
	// bassID means, this process is driving other processes' harmony generation
	// so leadTime should be > 0
	if(~bassID.notNil) {
		leadTime = max(leadTime, 0.05);
	};
	BP(name).leadTime = ~leadTime;
	BP(name)
}, type: \bp) => Fact(\melBP);



// chordBP: defaultParm = top note

PR(\arpeg1).clone {
	~nextNotePattern = #{ |inEvent|
			// if there is an event, we need to move to the next chord
		(inEvent.size > 0).if({
			~currentChord = ~chordStream.next(inEvent);
			~currentChordSize = ~currentChord.notes.size;
		});
	};
	~asPattern = #{ |inEvent|
		var	out, argPairs;
		if(~fitFactors.notNil) {
			inEvent = inEvent.copy.put(\fitnessOverride, ~fitFactors);
		};
		~currentChordSec = thisThread.seconds;
		out = Pbind(
			\note, inEvent[\chNotes].isNil.if({
				(~chords.size == 0).if({
					Error("Cannot play -- no chords have been provided to arpeg process").throw;
				}, {
					~nextNoteStream.value(inEvent)
				});
			}, {
					// fall back for midi input
				out = (notes: ~notes);
				ArpegPat(inEvent[\arpegType]).asPattern(
					Func(~fitFunc.value(out)).doAction(out, inEvent, ~getFit.value),
					inEvent)
			}),
			\noteCount, Pseries(0, Pfunc { |ev| max(1, ev[\note].freq.size) }, inf).drop(1).collect { |count, ev|
				if(~currentChordSize.notNil and: { count >= ~currentChordSize }) {
					// if we do this now, it'll release the nodes we want to slur
					// must wait until the nodes are updated -- then this will check for leftovers
					thisThread.clock.sched(0.05, e {
						ev[\voicer].tryPerform(\releaseSustainingBefore, ~currentChordSec,
							ev[\voicer].target.server.latency);
					});
				};
				count
			},
			#[\dur, \length, \gate], MicRh(inEvent[\microRhythm])
				.asPattern(~notePattern, inEvent),
			// \mode, (Pfunc({ ~currentChord.modeForEvent(inEvent) })),
			\mode, BPStream(\mode),
			\accent, Pseq([inEvent[\top][\accent] ?? { false }, Pn(false, inf)]),
			\acc, Pkey(\accent).collect(_.asInteger)
		);
		out = Pchain(BPStream(\defaults), out);
		~asPatternHook.(out) ?? { out };
	};
	~superPrepareSequence = ~prepareSequence;
	~prepareSequence = { |buf, parms|
		var result = ~superPrepareSequence.(buf, parms);
		~mode ?? { ~mode = parms.atBackup(\mode, buf.properties, parms) ?? { \default } };
		// put: do not remap MIDI notes
		// retain the diatonic information as is
		result.do { |ch| ch.put(\modeOverride, ~mode) };
		result
	};
	~modeForChordObjects = { |buf, parms|
		if(buf.properties.notNil) {
			buf.properties.atBackup(\mode, parms, currentEnvironment)
		} {
			parms.atBackup(\mode, currentEnvironment)
		}
		?? { \default }
	};
	~modeKeys = #[mode, root, scale, tuning, octave];
	~setDefault = { |key, value| ~defaults.setDefault(key, value) };
} => PR(\arpeg1LC);

(
bassID: \bass,
mode: nil,
octave: 5,
chords: \ch,
child: \arpeg1LC,
prKey: \chTop,
micro: \blockFollow,
arpeg: \block,
argPairs: nil,
eventKey: \voicerArtic, // \modalNoteArtic, // \voicerNote,
make: { |name|
	var p, buf, mode;
	BP(name).free;

	buf = MBM(0)[~chords];
	mode = ~mode ?? {
		if(Library.at(\clUseBufMode) == true) {
			buf.tryPerform(\properties).tryPerform(\at, \mode) ?? { \default }
		} {
			\default
		};
	};
	p = \newCh.eval(name, ~child, ~prKey, buf, nil, 4, ~micro, ~arpeg, nil, mode);
	p.child.defaults = PR(\clDefaults).copy.prep((), name);
	p.defaults = PR(\clDefaults).copy.prep((octave: ~octave), name);
	p.modeKeys = #[mode, root, scale, tuning, octave];
	p.setDefault = { |key, value|
		~child.setDefault(key, value);
		~defaults.setDefault(key, value);
	};
	p.setVoicerParms = { |parms, post|
		~defaults.setVoicerParms(parms, post);
		~child.defaults.setVoicerParms(parms, post);
	};
	p.v.import((abstractLiveCode: #[setPattern, valueForParm, parmIsPitch, beatsPerBar,
		setPhraseDur, phraseStringAt, prSetPhraseString, phraseSeq_]));
	p.defaultParm = \note;
	p.phrases = IdentityDictionary[
		\main -> PbindProxy([p.defaultParm, \dur], nil),
		\rest -> PbindProxy(\dur, Pfuncn { Rest(~clock.beatsPerBar) })
	];
	p.phraseDurs = IdentityDictionary[\main -> 4];
	p.phraseStrings = MultiLevelIdentityDictionary.new;
	p.parmMap = (
		note: (isPitch: true),
		acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/)
	);
	p.phraseSeq = \main;
	p.makeStreamForKey(\phraseSeq);
	p.topNote = Proto {
		// this is necessary to avoid circular reference: BP(name) --> ~topNote --> BP(name) -->
		// mild hack to hardcode the bp name
		~bpKey = name;
		~length = Pfunc { |ev|
			if(ev[\legato].isNil) {
				ev.use { ~sustain.value }
			} {
				ev[\dur] * ev[\legato]
			}
		};
		~gate = 0.5;
		~mode = mode;
		~octave = 5;
		~parmMap = p.parmMap;
		~defaultParm = p.defaultParm;
		~valueForParm = p[\valueForParm];
		~parmIsPitch = p[\parmIsPitch];
		~asPattern = {
			PnNilSafe(Plazy { |ev|
				var bp = BP(~bpKey),
				phrase = bp.phraseSeqStream.next(ev);
				if(bp.phrases[phrase].notNil) {
					bp[\lastPhrase] = phrase;
					Pbindf(
						Pfindur(bp.phraseDurs[phrase], bp.phrases[phrase]),
						\note, Pkey(\note) + (7 * BPStream(\octave)),
						// FFS, some bits downstream need it to be 'note';
						// other bits downstream need it to be 'freq';
						// I was a really bad coder back then, wasn't I?
						\freq, Pfunc { |ev|
							if(ev[\note].isKindOf(SequenceNote)) {
								ev[\note].freq
							} {
								ev[\note]
							}
						},
						\delta, Pkey(\dur),
						\length, BPStream(\length),
						\gate, BPStream(\gate),
						\mode, BPStream(\mode),
						\accent, Pfunc { |ev|
							if(ev[\accent].isNil) {
								ev[\acc].notNil and: { ev[\acc] > 0 }
							} {
								ev[\accent]
							}
						},
						\acc, Pkey(\accent).collect(_.asInteger)
					)
				} {
					"Phrase % not found in BP(%)".format(phrase, ~bpKey.asCompileString).warn;
					nil
				}
			}, inf);
		};
	};
	// note: putAction is a member variable of Proto, not an environment variable within the Proto!
	p.topNote.putAction = { |key, value, proto|
		var	streamKey;
		(value.isPattern
			or: {	streamKey = (key ++ "Stream").asSymbol;
				proto[streamKey].notNil })
		.if({
			proto[streamKey ?? { (key ++ "Stream").asSymbol }] = value.asStream;
		});
	};
	p.child.event.collIndex = name;
	p.child.event.eventKey = ~eventKey ?? { \voicerArtic };
	p.child.event.type = \voicerNote;  // ignored for artic types
	p.child.fitFunc = \chordFitInt;
	p.child.makeChordPattern = {
		var lastTop = 0, firstArg = { |val| val };
		Pclutch(Pxrand(~chords, inf), Pfunc { |ev|
			firstArg.(
				ev[\top][\note] != lastTop,
				lastTop = ev[\top][\note]
			)
		})
	};
	p.bassID = ~bassID;
	p.stopCleanup = {
		if(~event[\voicer].notNil) {
			~event[\voicer].releaseSustainingBefore(thisThread.seconds,
				Server.default.latency);
		};
	};
	p.bindVC = { |vc|
		var eventKey;
		Func(\bindVC).eval(vc);
		eventKey = vc.env[\eventKey];
		~child.event[\eventKey] = eventKey ?? { \voicerArtic };
		currentEnvironment
	};
	/*
	p.bindVC = { |vc|
		var temp;
		if(vc.exists) {
			~setVoicerParms.(
				vc.env[\argPairs].value(vc),
				vc.env[\postArgs].value(vc)
			);
			temp = vc.env[\extraChildParms].value(vc).debug("childparms");
			if(temp.notNil) {
				temp.keysValuesDo { |key, value|
					~child[key] = value;
				};
			};
			currentEnvironment
		} {
			"BP(%): VC(%) is dead".format(~collIndex.asCompileString, vc.collIndex.asCompileString).warn;
		};
	};
	*/

	TempoClock.default => p;
	p
}, type: \bp, defaultName: \ch) => Fact(\chordBP);



// arpegBP: defaultParm = index into chord, can play dyads

(
fit: \chordFitInt,
bassID: \bass,
chords: \ch,
mode: nil,  // use MIDIRecBuf's mode unless overridden here
make: { |name|
	var chords, mode;
	BP(name).free;
	// minor hack here. I don't want to override everything in arpeg1
	// but I do need the mode handling from arpeg1LC. So, chuck and replace.
	PR(\arpeg1) => BP(name);
	#[prepareSequence, superPrepareSequence, modeForChordObjects].do { |key|
		BP(name)[key] = PR(\arpeg1LC)[key];
	};
	PR(\abstractLiveCode).canWrap = true;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (eventKey: \default, type: \voicerArtic),
		userprep: {
			~parmMap[\chIndex] = (isPitch: true);
			~parmMap[\ch] = (alias: \chord);
			"1234567890".keep(~chords.size).do { |ch, i|
				~parmMap[\ch][ch] = i;
			};
		},
		defaultParm: \chIndex,
		parmMap: (
			chIndex: (isPitch: true),
			top: (isPitch: true, convertFunc: { |note, inEvent|
				var mode, degree;
				// especially! do not switch chord on an initialRest event
				if(note.isRest.not and: { note.isKindOf(SequenceNote) }) {
					mode = inEvent[\mode].asMode;
					degree = note.asFloat + (mode.scale.size * inEvent[\octave]);
					inEvent[\top] = (freq: degree, mode: inEvent[\mode]);
					if(degree != ~lastTop) {
						~lastTop = degree;
						inEvent[\nextChord] = true;
					};
					// normally isPitch:true should return a degree
					// but (freq: a, mode: b) is the format expected downstream
					inEvent[\top]
				}
				// it is ok to return nil here b/c BP's collect funcs turn it into a Rest()
			}),
			acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/),
			skip: ($0: 0, $1: 1, $2: 2, $3: 3, $4: 4, $5: 5),
		),
		// default event, hard to check if sus or legato changed
		// stuff in dummy values before other processing
		defaults: PR(\clDefaults).copy.prep(Pbind(
			\nextChord, false,
			\sustain, 0, \legato, 0, \skip, 2,
			\mode, Pfunc { ~child[\mode] ?? { \default } },
		), name),
		bassChanged: false,
		update: { |obj, changer ... args|
			if((changer == ~bassID)) {
				~bassChanged = true;
			};
		},
		bassID_: { |bassID|
			if(bassID.notNil) {
				BP.addDependant(currentEnvironment);
			} {
				BP.removeDependant(currentEnvironment);
			};
			~bassID = bassID;
			currentEnvironment
		},
		postDefaults: Pbind(
			\nextChord, Pfunc { |ev|
				var parentEvent,
				nextChord = ev[\nextChord] or: { ~chordNotes.isNil };
				if(~bassChanged or: { nextChord }) {
					parentEvent = (top: ev[\top], delta: ev[\dur], length: inf,
						arpegType: \block, microRhythm: \blockFollow,
						// these, fix later
						bassID: ~bassID, updateOnBass: true,
						convertTopFunc: \convertMode,
						mode: ev[\mode]
					);
					if(nextChord) {
						~child.nextNoteStream(parentEvent);
					} {
						~child.updateBass(parentEvent, ~bassID);
					};
					~bassChanged = false;
					~chordNotes = ~child.currentChord.lastFitNotes;
				}
				{ ~bassChanged } {

				};
				ev[\nextChord]
			},
			// assumes chordNotes are sorted in descending order
			// chordFitInt does this. Need to check others
			\degree, Pfunc { |ev|
				var offset = if(ev[\skip] <= 0) { 0 } { [0, ev[\skip]] };
				~chordNotes.wrapAt(ev[\chIndex].asFloat + offset).asFloat
			},
			\freq, Pfunc { |ev|
				ev[\mode].asMode.cps(ev[\degree])
			},
			\sustain, Pfunc { |ev|
				if(ev[\sustain] != 0) {
					ev[\sustain]
				} {
					ev[\dur] * ev[\legato]
				}
			},
			\accent, Pfunc { |ev|
				if(ev[\accent].isNil) {
					ev[\acc].notNil and: { ev[\acc] > 0 }
				} {
					ev[\accent]
				}
			},
			\acc, Pkey(\accent).collect(_.asInteger)
		).collect { |ev|
			if(~argPairs.notNil) {
				ev = ~argPairsStream.next(ev);
			};
			ev
		},
		modeKeys: #[mode, root, scale, tuning, octave],
		setDefault: { |key, value| ~defaults.setDefault(key, value) },
		setVoicerParms: { |parms, post| ~defaults.setVoicerParms(parms, post) }
	));
	PR(\abstractLiveCode).canWrap = false;
	BP(name).import((chTop: \acceptMIDIBuf));
	BP(name).child.fitFunc = ~fit;
	BP(name).bassID = ~bassID;
	BP(name).bindVC = Func(\bindVC).v;
	/*
	BP(name).bindVC = { |vc|
		var temp;
		if(vc.exists) {
			~argPairs = vc.env[\argPairs].value(vc);
			case
			{ ~argPairs.size > 0 } {
				~argPairs = Pbind(\argKeys, ~argPairs[0, 2..], *(~argPairs));
			};

			temp = vc.env[\extraChildParms].value(vc);
			if(temp.notNil) {
				temp.keysValuesDo { |key, value|
					~child[key] = value;
				};
			};
			currentEnvironment
		} {
			"BP(%): VC(%) is dead".format(~collIndex.asCompileString, vc.collIndex.asCompileString).warn;
		};
	};
	*/
	if(MBM.exists(0)) {
		chords = MBM(0)[~chords];
		if(chords.notNil) {
			mode = ~mode ?? {
				if(Library.at(\clUseBufMode) == true) {
					chords.tryPerform(\properties).tryPerform(\at, \mode) ?? { \default }
				} {
					\default
				};
			};
			BP(name).event[\mode] = mode;
			BP(name).child[\mode] = mode;
			chords => BP(name);
		};
	};
	BP(name)
},
type: \bp) => Fact(\arpegBP);

// helper function to auto-bind args from the VC object
{ |vc|
	var temp, chain;
	if(vc.exists) {
		~setVoicerParms.(
			vc.env[\argPairs].value(vc),
			vc.env[\postArgs].value(vc)
		);
		// if(~child.notNil) {
			temp = vc.env[\extraChildParms].value(vc);
			if(temp.notNil) {
				temp.keysValuesDo { |key, value|
				key.envirPut(value);
				// ~child[key] = value;
				};
			};
		// };
		temp = vc.env[\extraParms].value(vc);
		if(temp.notNil) {
			temp.keysValuesDo { |key, value|
				key.envirPut(value);
			};
		};
		currentEnvironment
	} {
		"BP(%): VC(%) is dead".format(~collIndex.asCompileString, vc.collIndex.asCompileString).warn;
	};
} => Func(\bindVC);

// make some modes available in all 12 keys
(maj: \major, dor: \dorian, phr: \phrygian, lyd: \lydian, mixo: \mixolydian, min: \minor, loc: \locrian)
.keysValuesDo { |postfix, scale|
	scale = Scale.at(scale);
	#["c", ["cs", "db"], "d", ["ds", "eb"], "e", "f", ["fs", "gb"], "g", ["gs", "ab"], "a", ["as", "bb"], "b"]
	.do { |rootStr, root|
		if(rootStr.isString) { rootStr = [rootStr] };
		rootStr.do { |rootName|
			ModalSpec(scale.semitones, 12, root) => Mode((rootName ++ postfix).asSymbol);
		};
	};
};
