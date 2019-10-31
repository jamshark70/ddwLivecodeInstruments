// for just intonation, we need a ModalSpec bound to the process
// that can look up the currently active tuning variant
// also shorten the syntax for performance

ModalSpecJI : ModalSpec {
	var <bpKey;

	bpKey_ { |key|
		if(BP.exists(key)) {
			bpKey = key
		};
	}

	bindClassName { ^\ModalSpec }

	cpsFunc_ { |func|
		cpsFunc = func;
	}

	cps { |degree, scAccidentals = false|
		var unmap = degree.unmapMode(this, scAccidentals);
		^if(cpsFunc.notNil) {
			cpsFunc.value(unmap)
		} {
			(unmap + tuning).midicps
		}
	}

	cpsOfKey { |midi|
		var ji, refKey, refFreq, octaves, relativeKeys, result;
		if(cpsFunc.notNil) {
			^cpsFunc.value(midi)
		} {
			// this cannot be in cpsFunc because then it's bound to the original, not a copy
			if(BP.exists(bpKey)) {
				if(BP(bpKey).v.respondsTo(\ji)) {
					ji = BP(bpKey).ji;
				};
				if(BP.exists(ji)) {
					ji = BP(ji);
					refKey = ji.lastRefKey;
					refFreq = ji.lastRefFreq;
					relativeKeys = midi - refKey;
					octaves = relativeKeys div: 12;
					result = ji.lastScale.wrapAt(relativeKeys) * (2 ** octaves) * refFreq;
				} {
					// "BP(%): No ji found, falling back to ET".format(~collIndex.asCompileString).warn;
					result = midi.midicps;
				}
			} {
				"No BP found, falling back to ET".warn;
				result = midi.midicps;
			};
			^result * tuning.midiratio
		}
	}
}
