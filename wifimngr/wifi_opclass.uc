// E4 global operating class table (802.11 Annex E, Table E-4)
// Each entry: { id, bw, ch: [[center_channel, [ctrl_channels...]], ...] }

const e4 = [
	{ id: 81, bw: 20, ch: [
		[1,[1]], [2,[2]], [3,[3]], [4,[4]], [5,[5]], [6,[6]], [7,[7]],
		[8,[8]], [9,[9]], [10,[10]], [11,[11]], [12,[12]], [13,[13]],
	]},
	{ id: 82, bw: 20, ch: [
		[14,[14]],
	]},
	{ id: 83, bw: 40, ch: [
		[1,[1]], [2,[2]], [3,[3]], [4,[4]], [5,[5]], [6,[6]], [7,[7]], [8,[8]], [9,[9]],
	]},
	{ id: 84, bw: 40, ch: [
		[5,[5]], [6,[6]], [7,[7]], [8,[8]], [9,[9]], [10,[10]], [11,[11]], [12,[12]], [13,[13]],
	]},
	{ id: 115, bw: 20, ch: [
		[36,[36]], [40,[40]], [44,[44]], [48,[48]],
	]},
	{ id: 116, bw: 40, ch: [
		[36,[36]], [44,[44]],
	]},
	{ id: 117, bw: 40, ch: [
		[40,[40]], [48,[48]],
	]},
	{ id: 118, bw: 20, ch: [
		[52,[52]], [56,[56]], [60,[60]], [64,[64]],
	]},
	{ id: 119, bw: 40, ch: [
		[52,[52]], [60,[60]],
	]},
	{ id: 120, bw: 40, ch: [
		[56,[56]], [64,[64]],
	]},
	{ id: 121, bw: 20, ch: [
		[100,[100]], [104,[104]], [108,[108]], [112,[112]],
		[116,[116]], [120,[120]], [124,[124]], [128,[128]],
		[132,[132]], [136,[136]], [140,[140]], [144,[144]],
	]},
	{ id: 122, bw: 40, ch: [
		[100,[100]], [108,[108]], [116,[116]], [124,[124]], [132,[132]], [140,[140]],
	]},
	{ id: 123, bw: 40, ch: [
		[104,[104]], [112,[112]], [120,[120]], [128,[128]], [136,[136]], [144,[144]],
	]},
	{ id: 124, bw: 40, ch: [
		[149,[149]], [153,[153]], [157,[157]], [161,[161]],
	]},
	{ id: 125, bw: 20, ch: [
		[149,[149]], [153,[153]], [157,[157]], [161,[161]],
		[165,[165]], [169,[169]], [173,[173]], [177,[177]],
	]},
	{ id: 126, bw: 40, ch: [
		[149,[149]], [157,[157]], [165,[165]], [173,[173]],
	]},
	{ id: 127, bw: 40, ch: [
		[153,[153]], [161,[161]], [169,[169]], [177,[177]],
	]},
	{ id: 128, bw: 80, ch: [
		[42,[36,40,44,48]], [58,[52,56,60,64]],
		[106,[100,104,108,112]], [122,[116,120,124,128]],
		[138,[132,136,140,144]], [155,[149,153,157,161]],
		[171,[165,169,173,177]],
	]},
	{ id: 129, bw: 160, ch: [
		[50,[36,40,44,48,52,56,60,64]],
		[114,[100,104,108,112,116,120,124,128]],
		[163,[149,153,157,161,165,169,173,177]],
	]},
	{ id: 130, bw: 80, ch: [
		[42,[36,40,44,48]], [58,[52,56,60,64]],
		[106,[100,104,108,112]], [122,[116,120,124,128]],
		[138,[132,136,140,144]], [155,[149,153,157,161]],
		[171,[165,169,173,177]],
	]},
	{ id: 131, bw: 20, ch: [
		[1,[1]], [5,[5]], [9,[9]], [13,[13]], [17,[17]], [21,[21]], [25,[25]], [29,[29]],
		[33,[33]], [37,[37]], [41,[41]], [45,[45]], [49,[49]], [53,[53]], [57,[57]], [61,[61]],
		[65,[65]], [69,[69]], [73,[73]], [77,[77]], [81,[81]], [85,[85]], [89,[89]], [93,[93]],
		[97,[97]], [101,[101]], [105,[105]], [109,[109]], [113,[113]], [117,[117]],
		[121,[121]], [125,[125]], [129,[129]], [133,[133]], [137,[137]], [141,[141]],
		[145,[145]], [149,[149]], [153,[153]], [157,[157]], [161,[161]], [165,[165]],
		[169,[169]], [173,[173]], [177,[177]], [181,[181]], [185,[185]], [189,[189]],
		[193,[193]], [197,[197]], [201,[201]], [205,[205]], [209,[209]], [213,[213]],
		[217,[217]], [221,[221]], [225,[225]], [229,[229]], [233,[233]],
	]},
	{ id: 132, bw: 40, ch: [
		[3,[1,5]], [11,[9,13]], [19,[17,21]], [27,[25,29]],
		[35,[33,37]], [43,[41,45]], [51,[49,53]], [59,[57,61]],
		[67,[65,69]], [75,[73,77]], [83,[81,85]], [91,[89,93]],
		[99,[97,101]], [107,[105,109]], [115,[113,117]], [123,[121,125]],
		[131,[129,133]], [139,[137,141]], [147,[145,149]], [155,[153,157]],
		[163,[161,165]], [171,[169,173]], [179,[177,181]], [187,[185,189]],
		[195,[193,197]], [203,[201,205]], [211,[209,213]], [219,[217,221]],
		[227,[225,229]],
	]},
	{ id: 133, bw: 80, ch: [
		[7,[1,5,9,13]], [23,[17,21,25,29]], [39,[33,37,41,45]], [55,[49,53,57,61]],
		[71,[65,69,73,77]], [87,[81,85,89,93]], [103,[97,101,105,109]],
		[119,[113,117,121,125]], [135,[129,133,137,141]], [151,[145,149,153,157]],
		[167,[161,165,169,173]], [183,[177,181,185,189]], [199,[193,197,201,205]],
		[215,[209,213,217,221]],
	]},
	{ id: 134, bw: 160, ch: [
		[15,[1,5,9,13,17,21,25,29]], [47,[33,37,41,45,49,53,57,61]],
		[79,[65,69,73,77,81,85,89,93]], [111,[97,101,105,109,113,117,121,125]],
		[143,[129,133,137,141,145,149,153,157]], [175,[161,165,169,173,177,181,185,189]],
		[207,[193,197,201,205,209,213,217,221]],
	]},
	{ id: 135, bw: 80, ch: [
		[7,[1,5,9,13]], [23,[17,21,25,29]], [39,[33,37,41,45]], [55,[49,53,57,61]],
		[71,[65,69,73,77]], [87,[81,85,89,93]], [103,[97,101,105,109]],
		[119,[113,117,121,125]], [135,[129,133,137,141]], [151,[145,149,153,157]],
		[167,[161,165,169,173]], [183,[177,181,185,189]], [199,[193,197,201,205]],
		[215,[209,213,217,221]],
	]},
	{ id: 136, bw: 20, ch: [
		[2,[2]],
	]},
	{ id: 137, bw: 320, ch: [
		[31,[1,5,9,13,17,21,25,29,33,37,41,45,49,53,57,61]],
		[63,[33,37,41,45,49,53,57,61,65,69,73,77,81,85,89,93]],
		[95,[65,69,73,77,81,85,89,93,97,101,105,109,113,117,121,125]],
		[127,[97,101,105,109,113,117,121,125,129,133,137,141,145,149,153,157]],
		[159,[129,133,137,141,145,149,153,157,161,165,169,173,177,181,185,189]],
		[191,[161,165,169,173,177,181,185,189,193,197,201,205,209,213,217,221]],
	]},
];

// Convert channel number to frequency based on opclass ID
function chan_to_freq(ch, opclass_id) {
	if (opclass_id <= 84) {
		if (ch == 14) return 2484;
		return 2407 + ch * 5;
	}
	if (opclass_id <= 130)
		return 5000 + ch * 5;
	// 6GHz
	return 5950 + ch * 5;
};

// Compute utilization % for one ctrl frequency from survey data.
// Returns null if the survey entry has no usable active/busy counters.
function freq_utilization(s) {
	if (!s || !s.active || s.busy == null)
		return null;
	if (s.active == 0)
		return null;
	let util = (s.busy * 100) / s.active;
	if (util < 0) util = 0;
	if (util > 100) util = 100;
	return util;
}

export function get_preferences(freq_info, survey) {
	let result = [];
	let by_freq = {};
	if (survey) {
		for (let s in survey)
			if (s?.frequency)
				by_freq[s.frequency] = s;
	}

	// Max regulatory txpower (dBm) across all enabled freqs in this band.
	// Used to penalize channels whose allowed txpower is below the band max.
	let max_txpower = null;
	for (let f, fi in freq_info) {
		if (fi?.txpower != null && (max_txpower == null || fi.txpower > max_txpower))
			max_txpower = fi.txpower;
	}

	for (let oc in e4) {
		let channels = [];
		let any_supported = false;

		for (let entry in oc.ch) {
			let ch = entry[0];
			let ctrl = entry[1];

			// Convert ctrl channels to frequencies
			let ctrl_freqs = [];
			let supported = true;
			let dfs = 0;
			let dfs_state = null;
			let cac_time = 0;
			let ch_txpower = null;
			let max_util = null;
			let min_noise = null;

			for (let c in ctrl) {
				let freq = chan_to_freq(c, oc.id);
				let fi = freq_info[freq];

				if (!fi) {
					supported = false;
					break;
				}

				push(ctrl_freqs, freq);
				if (fi.dfs) {
					dfs = 1;
					// Worst DFS state wins: unavailable > usable > available
					if (fi.dfs_state == "unavailable")
						dfs_state = "unavailable";
					else if (fi.dfs_state == "usable" && dfs_state != "unavailable")
						dfs_state = "usable";
					else if (dfs_state == null)
						dfs_state = fi.dfs_state;
					if (fi.cac_time > cac_time)
						cac_time = fi.cac_time;
				}
				if (ch_txpower == null || fi.txpower < ch_txpower)
					ch_txpower = fi.txpower;

				let s = by_freq[freq];
				if (s) {
					let u = freq_utilization(s);
					if (u != null && (max_util == null || u > max_util))
						max_util = u;
					if (s.noise != null && (min_noise == null || s.noise < min_noise))
						min_noise = s.noise;
				}
			}

			if (!supported) {
				push(channels, {
					channel: ch,
					score: 0,
					dfs: 0,
					ctrl_channels: ctrl,
				});
				continue;
			}

			any_supported = true;

			// With survey data: score in 1..100, idle=100, fully busy≈1,
			// additionally scaled by txpower ratio (ch allowed / band max).
			// Without survey data: reserved sentinel 255 ("unknown").
			// (Reserve 0 for "unsupported"; supported channels always ≥ 1.)
			let score = 255;
			if (max_util != null) {
				let util_score = 100 - int(max_util);
				// Multiply before divide to avoid ucode integer division truncating to 0.
				if (max_txpower && ch_txpower != null && ch_txpower < max_txpower)
					score = (util_score * ch_txpower) / max_txpower;
				else
					score = util_score;
				score = int(score);
				if (score < 1) score = 1;
				if (score > 100) score = 100;
			}

			// 2.4 GHz (opclass 81..84): only ch 1/6/11 are non-overlapping —
			// penalize every other channel to the minimum so they're rarely picked.
			if (oc.id >= 81 && oc.id <= 84 && ch != 1 && ch != 6 && ch != 11)
				score = (score == 255) ? 1 : (score > 1 ? 1 : score);

			let ch_info = {
				channel: ch,
				score,
				txpower: ch_txpower,
				dfs,
			};

			if (max_util != null)
				ch_info.utilization = int(max_util);
			if (min_noise != null)
				ch_info.noise = min_noise;

			if (dfs) {
				ch_info.dfs_state = dfs_state;
				ch_info.cac_time = cac_time;
			}

			ch_info.ctrl_channels = ctrl;
			push(channels, ch_info);
		}

		if (!any_supported)
			continue;

		push(result, {
			opclass: oc.id,
			bandwidth: oc.bw,
			channels,
		});
	}

	return result;
};
