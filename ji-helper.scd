// JI helper, leader and follower
// for each chord change, invoke leader first to choose the scale
// followers just use the last-selected scale

Proto {
	~isJIHelper = true;
	// for now, do not change this:
	// ~fillOne currently expects a 12-note chromatic scale
	~stepsPerOctave = 12;
	~prep = {
		~scales = Array.fill(4, ~fillOne);
		currentEnvironment
	};
	// bring a ratio within 1 <= r < 2
	~flattenOctave = { |ratio|
		ratio * (2 ** ratio.log2.trunc.neg)
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
		// keyPairs.debug("key pairs");
		~scales.minItem { |row, i|
			keyPairs.sum { |pair|
				var ratios = row.wrapAt(pair);
				if(ratios[1] > ratios[0]) { ratios.swap(0, 1) };
				// [pair, ratios[0], ratios[1], (ratios[0] / ratios[1]).asRational].debug("keys, ratio[0], ratio[1], quotient");
				(ratios[0] / ratios[1]).asFraction[1]  // denominator
			};
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
	~superPrep = ~prep;
	~prep = {
		~superPrep.();
		~lastScale = ~scales[1];
	};
	~superBestScale = ~bestScale;
	~bestScale = { |keys|
		~lastScale = ~superBestScale.(keys);
	};
	~superBestScaleToRef = ~bestScaleToRef;
	~bestScaleToRef = { |refKey, keys|
		~lastRefKey = refKey;
		~superBestScaleToRef.(refKey, keys);
	};
} => PR(\jiLeader);

PR(\jiHelper).clone {
	~source = \jiLeader;
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
