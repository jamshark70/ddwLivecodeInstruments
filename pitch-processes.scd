// some reusable pitch-playing processes

// one kind of nasty thing:
// I typically just use Mode(\default) and change its contents
// but, for just intonation, modes are stateful.
// so if I change the contents, I have to make new copies throughout the system.
// every pitch process, then, should implement ~mode_ and catch \modeChanged notifications

// if true: chord/arpegBP factories prefer mode stored in MIDIRecBuf properties
// if false: chord/arpegBP factories prefer \default mode
if(Library.at(\clUseBufMode).isNil) {
	Library.put(\clUseBufMode, false);
};

// helper function to auto-bind args from the VC object
// must be declared first
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
		temp = vc.env[\parmMap].value(vc);
		if(temp.notNil) {
			temp.keysValuesDo { |key, value|
				~parmMap.put(key, value);
			};
		};
		currentEnvironment
	} {
		"BP(%): VC(%) is dead".format(~collIndex.asCompileString, vc.collIndex.asCompileString).warn;
	};
} => Func(\bindVC);

// defaults handling is quite complex
// proc events can be an event or a pattern
// voicer argPairs can override
// then, setDefaults can override the override

// in a voicer factory:
// argPairs: go into defaults (pre-user-pattern)
// postArgs: analogous to postDefaults (post-user-pattern)
// extraChildParms: for chord processes, values to put into the arpeggiator object
// extraParms: values to put into the BP object
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
// in here, everything that refers to something in the Factory environment
// should be a function (lazy init)
chuckParms: (
	event: { (eventKey: \defaultPassRests, type: \voicerArtic, scAccidentals: true) },
	bassID: { ~bassID },
	defaultParm: \degree,
	// also lazy init the parmMap, otherwise all melBP instances share one parmMap
	// and one can corrupt another
	parmMap: { (
		degree: (isPitch: true),
		xpose: (
			isPitch: true,
			convertFunc: { |note, ev|
				var mode = ev[\mode].asMode;
				if(note.isRest.not and: { note.isKindOf(SequenceNote) and: { ev.isRest.not } }) {
					(mode.cpsOfKey(note.asFloat.unmapMode(mode, true)) / mode.cpsOfKey(0))
				} {
					1
				}
			},
			alias: \harmonic
		),
		acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/)
	) },
	defaults: { PR(\clDefaults).copy.prep((
		mode: ~mode ?? { \default },
		octave: ~octave ?? { 5 }
	), ~bpName) },
	// these environment references are in play-time functions, no need to wrap
	postDefaults: { Pchain(
		Plazy { BPStream(\voicerPostArgs, envir: ~defaults) },
		BPStream(\userPost),
		Pfunc { |ev|
			var mode, bassID;
			if(ev.isRest.not) {
				mode = ev[\mode].asMode;
				ev[\noteFrequency] = mode.cpsOfKey(
					(ev[\degree] + (ev[\octave] * mode.scale.size))
					.unmapMode(mode, ev[\scAccidentals])
				);
				ev[\freq] = { ~noteFrequency * ~harmonic };
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
	) },
	userPost: Pfunc { |ev| ev },
	bindVC: `(Func(\bindVC).v),
	modeKeys: #[mode, root, scale, tuning, octave],
	// pseudo-method definitions should be protected
	setDefault: `{ |... pairs|
		pairs.pairsDo { |key, value|
			~defaults.setDefault(key, value)
		};
	},
	set: `{ |... pairs| ~setDefault.(*pairs) },
	setVoicerParms: `{ |parms, post| ~defaults.setVoicerParms(parms, post) },
	ji: `{ ~event[\jiHelper] },
	ji_: `{ |key|
		if(key.isNil or: { BP.exists(key) and: { BP(key)[\isJIHelper] == true } }) {
			~event[\jiHelper] = key;
		} {
			"BP(%): BP(%) is not a just-intonation helper"
			.format(~collIndex.asCompileString, key.asCompileString)
			.warn;
		};
		currentEnvironment
	},
	mode_: `{ |mode|
		var modeObj = mode.asMode;
		if(modeObj.value.isKindOf(ModalSpecJI)) {
			~mode = modeObj.value.copy.bpKey_(~collIndex);
		} {
			~mode = mode;
		};
		~defaults.setDefault(\mode, ~mode);
		~addModeWatcher.(modeObj);
	},
	addModeWatcher: `{ |modeObj|
		~modeWatcher.remove;
		~modeWatcher = SimpleController(modeObj)
		.put(\modeChanged, inEnvir { |obj|
			~mode_.value(obj);  // important for copying ModalSpecJI
		})
		.put(\free, inEnvir {
			"BP(%): Mode(%) has been freed, process may break"
			.format(~collIndex.asCompileString, ~mode.asCompileString)
			.warn;
			~modeWatcher.remove;
		});
		currentEnvironment
	},
	preset: `{ |presetName| \preset.eval(presetName, ~collIndex) }
),
make: { |name|
	var leadTime = ~leadTime, parms;
	BP(name).free;
	// resolve lazy-init functions within this environment; unwrap `refFunctions
	~bpName = name;
	parms = ~chuckParms.collect { |value| value.value };
	PR(\abstractLiveCode).chuck(BP(name), nil, parms);
	// bassID means, this process is driving other processes' harmony generation
	// so leadTime should be > 0
	if(~bassID.notNil) {
		leadTime = max(leadTime, 0.05);
	};
	BP(name).leadTime = leadTime;
	BP(name).mode = ~mode;
	// optionally: /make(melBP:name(ji:\jiHelperKey)) (just intonation)
	if(~ji.notNil) { BP(name).ji = ~ji };
	// hm, there's no 'prep' so apply layer here
	BP(name).event[\layerID] = UniqueID.next;
	BP(name)
}, type: \bp) => Fact(\melBP);

// melBP that plays two pitches, e.g. one for an osc and another for a filter
// bit icky hacking done here
{
	var parms = Fact(\melBP).v[\chuckParms].copy;
	parms.putAll((
		ffreqCtl: { ~ffreqCtl },
		rootOctave: { ~rootOctave },
		defaultParm: \filtDegree,
		parmMap: (
			filtDegree: (isPitch: true),
			degree: (isPitch: true),
			acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/)
		),
		defaults: { PR(\clDefaults).copy.prep((
			mode: ~mode ?? { \default },
			octave: ~octave ?? { 5 },
			rootOctave: ~rootOctave,
		), ~bpName) },
		userPost: Pfunc { |ev|
			var mode = ev[\mode].asMode;
			ev[~ffreqCtl] = mode.cps(
				ev[\filtDegree] + (ev[\octave] * mode.scale.size),
				ev[\scAccidentals]
			);
			ev[\freq] = ev[\freq] * (2 ** (ev[\rootOctave] - ev[\octave]))
		}
	));
	Fact(\melBP).v.copy
	.put(\chuckParms, parms)
	.put(\ffreqCtl, \ffreq)
	.put(\rootOctave, 3)
	=> Fact(\melFiltBP);
}.value;

// chordBP: defaultParm = top note

// first, new clone of chord object with just-intonation support
// this needs to be done in the chord object
// because here is the only place that is certain to have all the chord notes
PR(\chordModeSeg).clone {
	~superAsPattern = ~asPattern;
	~asPattern = { |inEvent, fitFunc|
		var out = ~superAsPattern.(inEvent, fitFunc),
		mode = ~mode.asMode,
		keys = ~lastFitNotes.asFloat.unmapMode(mode),
		refKey,
		ji;

		if(BP.exists(inEvent[\jiHelper]) and: { BP(inEvent[\jiHelper])[\isJIHelper] == true }) {
			ji = BP(inEvent[\jiHelper]);
			// sets lastScale and lastRefKey
			~jiScale = ji.bestScaleToRef(keys[0], keys);
			// refFreq = mode root (midicps) * chosen scale ratio
			// but scale is arranged with refKey at [0]
			// so scale root is -refKey: invert the interval and raise an octave
			// obtain from ji because we might be following another process's tuning
			refKey = ji.lastRefKey - mode.root;
			ji.lastRefFreq = mode.root.midicps / ~jiScale.wrapAt(refKey.neg)
			// -0.01 is a slight hack.
			// If refKey *is* the mode root, then the division does not go down
			// but instead stays on the same pitch. So it's wrong to add the octave
			// in that case. To avoid, subtract a small amount that will not affect refKey = 1
			* (2 ** ((refKey - 0.01) div: 12 + 1));
		};
		out
	};
} => PR(\chordJISeg);

PR(\arpeg1).clone {
	~chordProto = \chordJISeg;

	~nextNotePattern = #{ |inEvent|
			// if there is an event, we need to move to the next chord
		(inEvent.size > 0).if({
			~currentChord = ~chordStream.next(inEvent);
			~currentChordSize = ~currentChord.notes.size;
		});
	};
	~asPattern = #{ |inEvent|
		var	out, argPairs;
		var eventProto = inEvent[\top].copy
		// yeah... data pollution...
		.put(\dur, nil).put(\delta, nil).put(\length, nil)
		.put(\note, nil).put(\freq, nil)
		.parent_(nil).proto_(nil);
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
					if(ev[\voicer].notNil) {
						thisThread.clock.sched(0.05, inEnvir {
							ev[\voicer].tryPerform(\releaseSustainingBefore, ~currentChordSec,
								ev[\voicer].target.server.latency);
						});
					};
				};
				count
			},
			#[\dur, \length, \gate], MicRh(inEvent[\microRhythm])
				.asPattern(~notePattern, inEvent),
			\mode, BPStream(\mode),
			// user code needs to depend on degree/octave, for other pitch processes
			// but this process represents pitch as a SequenceNote, so, extract
			#[degree, octave], Pfunc { |ev|
				var degree = ev[\note].tryPerform(\asFloat),
				mode = ev[\mode].asMode;
				if(degree.notNil) {
					[degree % mode.scale.size, degree div: mode.scale.size]
				} {
					[Rest(0), Rest(5)]
				}
			},
			\accent, Pseq([inEvent[\top][\accent] ?? { false }, Pn(false, inf)]),
			\acc, Pkey(\accent).collect(_.asInteger)
		);
		out = Pchain(BPStream(\defaults), out, Pfunc { |ev| ev.proto = eventProto });
		~asPatternHook.(out) ?? { out };
	};
	~superPrepareSequence = ~prepareSequence;
	~prepareSequence = { |buf, parms|
		var result = ~superPrepareSequence.(buf, parms);
		~mode ?? { ~mode = parms.atBackup(\mode, buf.properties, parms) ?? { \default } };
		// put: do not remap MIDI notes
		// retain the diatonic information as is
		result.do { |ch| ch.put(\modeOverride, ~mode).put(\scAccidentals, true) };
		result
	};
	// total override of mode
	~mode_ = { |mode|
		~mode = mode;
		~event[\mode] = mode;
		~chords.do { |ch| ch.mode = mode };
		currentEnvironment
	};
	~modeForChordObjects = { |buf, parms|
		BP(~collIndex).mode
	};
	~modeKeys = #[mode, root, scale, tuning, octave];
	~setDefault = { |... pairs|
		pairs.pairsDo { |key, value|
			// bit of a hack: for ~fitFunc, the mode must be stored in all chords
			// because, if the chord mode doesn't match the event mode,
			// it will try to transpose chords. That's good for general chucklib usage,
			// but here, I want the runtime selection always to override.
			if(key == \mode) {
				if(value.isPattern) {
					"Chord process: Patterns are not supported for \mode".warn;
				} {
					value = value.asMode.value;
					~mode = value;  // note, don't copy ModalSpecJI objects here
					~chords.do { |ch| ch.put(\mode, value).put(\modeOverride, value) };
				};
			};
			~defaults.setDefault(key, value);
		};
	};
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
	var p, buf, mode,
	factParms = currentEnvironment;
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
	// object to hold defaults for individual note playback (including voicer parameters)
	// we need another defaults object for the topNote (esp. for 'octave')
	// but topNote, below, will create it
	p.child.defaults = PR(\clDefaults).copy.prep((), name);
	p.modeKeys = #[mode, root, scale, tuning, octave];
	p.setDefault = { |... pairs|
		pairs.pairsDo { |key, value|
			~child.setDefault(key, value);
			~topNote.postDefaults.setDefault(key, value);
		};
	};
	p.set = { |... pairs| ~setDefault.(*pairs) };
	p.setVoicerParms = { |parms, post|
		~topNote.postDefaults.setVoicerParms(parms, post);
		~child.defaults.setVoicerParms(parms, post);
	};
	p.v.import((abstractLiveCode: #[
		setPattern, valueForParm, valueIsRest, parmIsPitch, parmIsDefault,
		getParmHandler, fixParmMap, defaultParmMaps, addPitchConversion,
		beatsPerBar, setPhraseDur, phraseStringAt, prSetPhraseString, phraseSeq_, swing_,
		preset, presets_, printPreset
	]));
	p.defaultParm = \note;
	p.phrases = IdentityDictionary[
		\main -> PbindProxy([p.defaultParm, \delta, \dur], nil),
		\rest -> PbindProxy(\dur, Pfuncn { Rest(~clock.beatsPerBar) })
	];
	p.phraseDurs = IdentityDictionary[
		\main -> { ~clock.beatsPerBar },
		\rest -> { ~clock.beatsPerBar }
	];
	p.phraseStrings = MultiLevelIdentityDictionary.new;
	p.parmMap = (
		note: (isPitch: true),
		xpose: (isPitch: true, convertFunc: { |note, ev|
			// *probably* note comes first
			if(ev[\note].notNil and: { note.isRest.not }) {
				ev[\note] = ev[\note] + note.asFloat
			};
			note.asFloat  // save, if 'note' comes later, apply it then
		}),
		acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/),
		newChord: ($-: \new, $=: \hold, $.: \plane, default: $=)
	);
	p.fixParmMap;
	// unfortunately this has to be stashed in the event prototype
	// because \clDefaults evaluates after user patterns, thus overwrites
	p.event[\newChord] = \hold;
	p.phraseSeq = \main;
	p.makeStreamForKey(\phraseSeq);
	p.topNote = Proto {
		// this is necessary to avoid circular reference: BP(name) --> ~topNote --> BP(name) -->
		// mild hack to hardcode the bp name
		~bpKey = name;
		~postDefaults = PR(\clDefaults).copy.prep(
			Pbind(
				\length, Pfunc { |ev|
					if(ev[\legato].isNil) {
						ev.use { ~sustain.value }
					} {
						ev[\dur] * ev[\legato]
					}
				},
				\gate, 0.5,
				\mode, mode,
				\octave, factParms[\octave] ?? { 5 }
			),
			name
		);
		~mode_ = { |mode|
			~postDefaults.setDefault(\mode, mode);
			currentEnvironment
		};
		~parmMap = p.parmMap;
		~defaultParm = p.defaultParm;
		~valueForParm = p[\valueForParm];
		~parmIsPitch = p[\parmIsPitch];
		~asPattern = {
			if(~octaveStream.isNil) {
				~octaveStream = ~octave.asStream;
			};
			PnNilSafe(Plazy { |ev|
				var bp = BP(~bpKey),
				phrase = bp.phraseSeqStream.next(ev);
				if(bp.phrases[phrase].notNil) {
					bp[\lastPhrase] = phrase;
					// Pchain inverts order: first to evaluate is written last
					// so this is: phrase pattern --> rest check --> postDefaults --> topNote processing
					Pchain(
						Pif(
							Pfunc { |ev| phrase == \rest or: { ev.isRest } },
							// more hack: parent process requires length to be populated
							// and force delta to be a Rest, so that nothing happens upstream
							Pfunc { |ev| ev.put(\length, 0.01).put(\delta, Rest(ev[\dur])) },
							Pbindf(
								BPStream(\postDefaults),
								\note, Pfunc { |ev|
									ev[\note] + (7 * ev[\octave])
								},
								// FFS, some bits downstream need it to be 'note';
								// other bits downstream need it to be 'freq';
								// I was a really bad coder back then, wasn't I?
								\freq, Pfunc { |ev|
									if(ev[\note].isKindOf(SequenceNote)) {
										ev[\note].freq + (ev[\xpose] ?? { 0 })
									} {
										ev[\note]
									}
								},
								\delta, Pkey(\dur),
								\accent, Pfunc { |ev|
									if(ev[\accent].isNil) {
										ev[\acc].notNil and: { ev[\acc] > 0 }
									} {
										ev[\accent]
									}
								},
								\acc, Pkey(\accent).collect(_.asInteger)
							)
						),
						if(bp.phraseDurs[phrase].notNil) {
							Pfindur(bp.phraseDurs[phrase], bp.phrases[phrase])
						} {
							bp.phrases[phrase]
						},
						(isTopNotePattern: true)
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
			var newChord = ev[\top][\newChord];
			newChord == \new or: {  // 'or': \new *always* forces new chord
				newChord == \hold and: {  // \hold *might* go new; \plane *never* does
					firstArg.(
						ev[\top][\note] != lastTop,
						lastTop = ev[\top][\note]
					)
				}
			}
		})
	};
	p.bassID = ~bassID;
	p.mode_ = { |mode|
		var modeObj = mode.asMode;
		if(modeObj.value.isKindOf(ModalSpecJI)) {
			~mode = modeObj.value.copy.bpKey_(~collIndex);
		} {
			~mode = mode;
		};
		~addModeWatcher.(modeObj);
		~event[\mode] = ~mode;
		~child !? { ~child.mode = ~mode };
		if(~topNote.isKindOf(Proto)) { ~topNote.mode = ~mode };
		currentEnvironment  // .put(\mode, ~mode);
	};
	p.addModeWatcher = Fact(\melBP).chuckParms[\addModeWatcher].value;
	p.freeCleanup = {
		~modeWatcher.remove;
		~topNote.tryPerform(\freeCleanup);
		~userfree.();
	};
	p.ji = Fact(\melBP).chuckParms[\ji].value;
	p.ji_ = {
		if(~child.notNil) { ~child.event[\jiHelper] = ~event[\jiHelper] };
		currentEnvironment
	} <> Fact(\melBP).chuckParms[\ji_].value;
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
		~child.event.type = \voicerNote;  // ignored for artic types
		currentEnvironment
	};
	p.superReset = p[\reset];
	p[\reset] = {
		~superReset.();
		~makeStreamForKey.(\phraseSeq);
		~makeStreamForKey.(\defaults);
		~makeStreamForKey.(\postDefaults);
		~userreset.();
	};
	// You would think I don't have to do this... but:
	// If a cll event is a true rest, e.g. 'x', then the top note is a Rest()
	// and not a number -- but top notes being numbers is a precondition for
	// ProtoEvent(\macroRh) to forward to the child process. So the child never
	// fires and never has an opportunity to cut off hanging notes.
	// So the parent has to do it, here.
	p[\superPatternTop] = p[\patternAvecTop];
	p[\patternAvecTop] = {
		~superPatternTop.value.collect { |ev|
			var sec;
			ev[\mode] = ev[\top][\mode];
			if(ev[\top].isRest and: {
				ev[\top][\initialRest] != true and: {
					~child.currentChordSec.notNil
				}
			}) {
				// note trigger times == ~child.currentChordSec
				// but test for release is "<" so we need a slight difference
				if(ev[\voicer].notNil) {
					ev[\voicer].tryPerform(\releaseSustainingBefore, ~child.currentChordSec + 0.01,
						ev[\voicer].target.server.latency);
				};
			};
			ev
		};
	};
	p[\preset] = { |presetName| \preset.eval(presetName, ~collIndex) };
	// rests are now inside topNote. Need to be aware of the clock.
	p['clock_'] = { |clock|
		~clock = clock;
		~topNote.put(\clock, clock);
		currentEnvironment
	};
	TempoClock.default => p;
	Mode(mode) => p;
	p.event.layerID = UniqueID.next;
	p.child.event.layerID = p.event.layerID;
	if(~ji.notNil) { p.ji = ~ji };
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
	#[chordProto, prepareSequence, superPrepareSequence, modeForChordObjects].do { |key|
		BP(name)[key] = PR(\arpeg1LC)[key];
	};
	PR(\abstractLiveCode).canWrap = true;
	PR(\abstractLiveCode).chuck(BP(name), nil, (
		event: (
			eventKey: \defaultPassRests, type: \voicerArtic, scAccidentals: true,
			layerID: UniqueID.next
		),
		userprep: {
			~parmMap[\chIndex] = (isPitch: true);
			~parmMap[\ch] = (alias: \chord);
			"1234567890".keep(~chords.size).do { |ch, i|
				~parmMap[\ch][ch] = i;
			};
		},
		userfree: { ~modeWatcher.remove },
		defaultParm: \chIndex,
		parmMap: (
			chIndex: (isPitch: true),
			top: (isPitch: true, convertFunc: { |note, inEvent|
				var mode, degree;
				// especially! do not switch chord when 'top' has an initialRest event
				// also check inEvent: if 'top' changes on an inEvent rest,
				// then the chord never updates unless we postpone the change here.
				if(note.isRest.not and: { note.isKindOf(SequenceNote) and: { inEvent.isRest.not } }) {
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
				// it is ok to return nil here b/c BP's collect funcs replace it with a default
			}),
			acc: ($>: 1, $-: 0, $.: 0, default: $-/*, alias: \accent*/),
			skip: ($0: 0, $1: 1, $2: 2, $3: 3, $4: 4, $5: 5),
		),
		// default event, hard to check if sus or legato changed
		// stuff in dummy values before other processing
		defaults: PR(\clDefaults).copy.prep(Pbind(
			\nextChord, false,
			\sustain, 0, \legato, 0, \skip, 0,
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
						mode: ev[\mode],
						jiHelper: ev[\jiHelper]
					);
					if(nextChord) {
						~child.nextNoteStream(parentEvent);
					} {
						~child.updateBass(parentEvent, ~bassID);
					};
					~bassChanged = false;
					~chordNotes = ~child.currentChord.lastFitNotes;
				};
				ev[\nextChord]
			},
			// assumes chordNotes are sorted in descending order
			// chordFitInt does this. Need to check others
			\degree, Pfunc { |ev|
				var offset = if(ev[\skip] <= 0) { 0 } { [0, ev[\skip]] },
				oct = ev[\chIndex] div: 7;  // octave size hardcoded elsewhere too, be careful
				~chordNotes.wrapAt(ev[\chIndex].asFloat % 7 + offset).asFloat + (7 * oct)
			},
			\freq, Pfunc { |ev|
				var mode = ev[\mode].asMode;
				mode.cpsOfKey(ev[\degree].unmapMode(mode, ev[\scAccidentals]))
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
		mode_: { |mode|
			var modeObj = mode.asMode;
			if(modeObj.value.isKindOf(ModalSpecJI)) {
				~mode = modeObj.value.copy.bpKey_(~collIndex);
			} {
				~mode = mode;
			};
			~addModeWatcher.(modeObj);
			~event[\mode] = ~mode;
			~child !? { ~child.mode = ~mode };
			if(~topNote.isKindOf(Proto)) { ~topNote.mode = ~mode };
			currentEnvironment  // .put(\mode, ~mode);
		},
		addModeWatcher: Fact(\melBP).chuckParms[\addModeWatcher].value,
		modeKeys: #[mode, root, scale, tuning, octave],
		setDefault: { |... pairs|
			pairs.pairsDo { |key, value|
				~defaults.setDefault(key, value)
			};
		},
		set: { |... pairs| ~setDefault.(*pairs) },
		setVoicerParms: { |parms, post| ~defaults.setVoicerParms(parms, post) },
		preset: { |presetName| \preset.eval(presetName, ~collIndex) }
	));
	PR(\abstractLiveCode).canWrap = false;
	BP(name).import((chTop: \acceptMIDIBuf));
	BP(name).child.fitFunc = ~fit;
	BP(name).bassID = ~bassID;
	BP(name).bindVC = Func(\bindVC).v;
	BP(name).ji = Fact(\melBP).chuckParms[\ji].value;
	BP(name).ji_ = Fact(\melBP).chuckParms[\ji_].value;
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
			BP(name).mode = mode;
			chords => BP(name);
		};
	};
	if(~ji.notNil) { BP(name).ji = ~ji };
	BP(name)
},
type: \bp) => Fact(\arpegBP);

// make some modes available in all 12 keys
(maj: \major, dor: \dorian, phr: \phrygian, lyd: \lydian, mixo: \mixolydian, min: \minor, loc: \locrian)
.keysValuesDo { |postfix, scale|
	scale = Scale.at(scale);
	#["c", ["cs", "db"], "d", ["ds", "eb"], "e", "f", ["fs", "gb"], "g", ["gs", "ab"], "a", ["as", "bb"], "b"]
	.do { |rootStr, root|
		if(rootStr.isString) { rootStr = [rootStr] };
		rootStr.do { |rootName|
			ModalSpecJI(scale.semitones, 12, root) => Mode((rootName ++ postfix).asSymbol);
		};
	};
};

if(Mode.exists(\default).not) { Mode(\cmaj) => Mode(\default) };

if(MBM.exists(0).not) {
	MIDIBufManager(TempoClock.default, nil) => MBM.prNew(0);
};

MIDIRecBuf(\bigch, [
	[60, 64, 67, 69, 74, 77, 79,
		60, 64, 65, 71, 74, 76, 81,
		60, 62, 65, 67, 74, 76, 81,
		60, 67, 69, 74, 77, 79, 84,
		60, 64, 67, 72, 76, 79, 84],
	Array.fill(7*5, 0.1).putSeries(6, 13, 34, 1),
	0.1, 0.5
].asNotes, properties: (type: \ch, mode: \cmaj)) => MBM(0);

MIDIRecBuf(\smallch, [
	[60, 64, 67,  60, 65, 67,  60, 64, 69,  60, 62, 69,  60, 64, 71,  60, 62, 71,  60, 65, 71],
	Array.fill(3*7, 0.1).putSeries(2, 5, 20, 1),
	0.1, 0.5
].asNotes, properties: (type: \ch, mode: \cmaj)) => MBM(0);

MIDIRecBuf(\one, [
	[60],
	[0.1],
	0.1, 0.5
].asNotes, properties: (type: \ch, mode: \cmaj)) => MBM(0);

MIDIRecBuf(\two, [
	[[48, 50, 52, 53, 55, 57, 59], 60].lace(14),
	[0.1, 1].lace(14),
	0.1, 0.5
].asNotes, properties: (type: \ch, mode: \cmaj)) => MBM(0);

if(BP.exists(\lead).not) {
	PR(\jiLeader) => BP(\lead);
	PR(\jiFollow) => BP(\follow);
};
