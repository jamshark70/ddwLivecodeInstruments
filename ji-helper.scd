// JI helper, leader and follower
// for each chord change, invoke leader first to choose the scale
// followers just use the last-selected scale

Proto {
	~isJIHelper = true;
	~debug = false;
	// for now, do not change this:
	// ~fillOne currently expects a 12-note chromatic scale
	~stepsPerOctave = 12;
	// preferred forms for individual intervals
	~preferred = [
		1, 16/15,  // C, C#  16/15 = P4 - M3
		9/8, 6/5,  // D, D#  6/5 = pure m3
		5/4,       // E
		4/3, 45/32,// F, F# 45/32 = M2 + M3
		3/2, 8/5,  // G, G#  8/5 = down M3 + P8
		5/3, 9/5,  // A, A#  9/5 = P5 + m3, so m7 chord is in tune
		15/8       // B     15/8 = P5 + M3
	];
	// how important is each interval? P4/P5 very important, 2nd/7th medium important, 3rd not so much
	// this is important for 0 3 5 trichord where 0 and 5 should be up a comma
	// and the minor third should be slightly narrow
	// (it really sounds better that way, closer to Pythagorean)
	~weights = [
		0,  // unison
		1, 3,  // m2 low, M2 mid
		2, 2,  // thirds medium importance
		4, 1,  // P4 high, tritone low
		4,     // P5 high
		2, 2,  // m6 M6 medium
		3, 1   // m7 mid, M7 low
	];
	~prep = {
		~scales = Array.fill(4, ~fillOne);
		currentEnvironment
	};
	// bring a ratio within 1 <= r < 2
	~flattenOctave = { |ratio|
		ratio * (2 ** ratio.log2.trunc.neg)
	};
	// un-flatten octave, based on key
	~getRatio = { |key, scaleIndex|
		~scales[scaleIndex].wrapAt(key) * (2 ** (key div: 12))
	};
	~syntonic = 80/81;
	~fillOne = { |offset = 0|
		var out = Array.newClear(12);
		12.do { |i|
			var commaK;
			i = i - 5;
			commaK = (i + offset) div: 4;
			out.wrapPut(i * 7, ~flattenOctave.((1.5 ** i) * (~syntonic ** commaK)));
		};
		out
	};
	// chromatic notes, not scale degrees
	~bestScale = { |keys|
		var keyPairs = Array(keys.size * (keys.size - 1));
		(keys.size - 1).do { |i|
			(i + 1 .. keys.size - 1).do { |j|
				keyPairs.add([keys[i], keys[j]]);
			};
		};
		if(~debug == true) {
			keys.debug("bestScale keys");
			keyPairs.debug("key pairs");
		};
		~scales.maxItem { |row, i|
			var sum;
			if(~debug == true) { row.asRational.debug("testing") };
			sum = keyPairs.sum { |pair|
				var ratio, adding;
				if(pair[0] < pair[1]) { pair.swap(0, 1) };  // want [0] to be bigger
				ratio = ~getRatio.(pair, i);
				ratio = ~flattenOctave.(ratio[0] / ratio[1]);
				adding = if(ratio.equalWithPrecision(~preferred.wrapAt(pair[0] - pair[1]))) {
					~weights.wrapAt(pair[0] - pair[1])
				} { 0 };
				if(~debug == true) {
					[pair, row.wrapAt(pair).asRational, ratio.asRational, ~preferred.wrapAt(pair[0] - pair[1]).asRational, adding]
					.debug("keys, ratios, quotient, preferred, adding");
				};
				adding
			};
			if(~debug == true) { sum.debug("sum for scale") };
			sum
		};
	};
	~bestScaleToRef = { |refKey, keys|
		~bestScale.(keys - refKey);
	};
	// given ref pitch and keys, return ratio for each key relative to reference
	~keysToRatios = { |refKey, keys|
		var octaves;
		keys = keys - refKey;
		octaves = keys div: ~stepsPerOctave;  // maybe don't hardcode later?
		~bestScale.(keys).wrapAt(keys) * (2 ** octaves);
	};
	~keysToFreqs = { |refFreq, refKey, keys|
		refFreq * ~keysToRatios.(refKey, keys)
	};
} => PR(\jiHelper);

PR(\jiHelper).clone {
	~defaultMode = \default;
	~superPrep = ~prep;
	~prep = {
		~superPrep.();
		~lastScale = ~scales[1];
		// we must initialize to sensible values
		~lastRefKey = Mode(~defaultMode).root;
		~lastRefFreq = ~lastRefKey.midicps;
		// now the tricky part
		// if you change mode before the jiLeader has been called,
		// we need to update lastRefKey and lastRefFreq
		// ... but after it's called, we should use the new data
		~modeWatcher = SimpleController(Mode(~defaultMode))
		.put(\modeChanged, inEnvir { |modeObj|
			~lastRefKey = modeObj.root;
			~lastRefFreq = ~lastRefKey.midicps;
		})
		.put(\free, inEnvir { ~modeWatcher.remove });
		currentEnvironment
	};
	~freeCleanup = { ~modeWatcher.remove };
	~superBestScale = ~bestScale;
	~bestScale = { |keys|
		~lastScale = ~superBestScale.(keys);
	};
	~superBestScaleToRef = ~bestScaleToRef;
	~bestScaleToRef = { |refKey, keys|
		// now I have my own setting for refKey
		// so I don't have to update on Mode anymore
		~modeWatcher.remove;
		~modeWatcher = nil;
		~lastRefKey = refKey;  // ji "client" will decide lastRefFreq
		~superBestScaleToRef.(refKey, keys);
	};
} => PR(\jiLeader);

PR(\jiHelper).clone {
	~source = \lead;
	~prep = {
		if(~sourceIsValid.(~source).not) {
			"BP(%): BP(%) is not a just-intonation helper, be sure to set a valid source"
			.format(~collIndex.asCompileString, ~source.asCompileString)
			.warn;
		};
		currentEnvironment
	};
	~sourceIsValid = { |key|
		BP.exists(key) and: { BP(key)[\lastScale].isArray }
	};
	~source_ = { |key|
		if(~sourceIsValid.(key)) {
			~source = key;
		} {
			Error("BP(%): BP(%) is not a just-intonation helper".format(
				~collIndex.asCompileString, key.asCompileString
			)).throw;
		};
		currentEnvironment
	};

	~bestScale = { |keys| BP(~source).lastScale };
	// jiFollow should not override anything from source
	// so, ignore refKey here
	~bestScaleToRef = { |refKey, keys| BP(~source).lastScale };

	~lastScale = { BP(~source).lastScale };
	~lastRefKey = { BP(~source).lastRefKey };
	~lastRefFreq = { BP(~source).lastRefFreq };

	// jiFollow should not override anything from source
	~lastScale_ = { currentEnvironment };
	~lastRefKey_ = { currentEnvironment };
	~lastRefFreq_ = { currentEnvironment };
} => PR(\jiFollow);
