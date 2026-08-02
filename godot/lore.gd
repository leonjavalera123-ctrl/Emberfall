# EMBERFALL: 1940 — lore.gd
# The world bible, transcribed from LORE.md into the project. LORE.md itself
# lives one level above res:// (C:\Users\leonj\Emberfall\LORE.md), so it is not
# addressable at runtime and would never be exported — the text has to live
# here. Page 0 is the world; pages 1-4 match the faction ids used everywhere
# else (EFWorld.FACTIONS, menu.FACTIONS, buildings.FACTION_TABS).

class_name EFLore
extends RefCounted

const PAGES := {
0: {
	"title": "THE CRADLE WAR",
	"body": """[color=#e39429]THIS IS NOT OUR EARTH.[/color]  Its history bent in 1861 and never bent back.

[color=#e39429]1861 — THE EMBERFALL.[/color]  For nine nights the sky burned. Meteor storms fell across every continent, and buried in the fallen rock was [b]emberstone[/b] — a dull grey ore, cold and dead until heated, and then... not.

[color=#e39429]1862-1869 — THE LONG WINTER.[/color]  The dust of the Fall veiled the sun. Seven years of grey skies and black harvests. The old empires — proud, ancient, certain — starved to death in their palaces. The old map died with them.

[color=#e39429]1870s — THE EMBER RUSH.[/color]  The survivors discovered what emberstone does: a fistful, once ignited, burns furnace-hot for weeks. Steam engines that once filled a mill house now fit on a wagon, then on a man's back. Whoever held ember veins held the future. The Rush redrew every border in blood and claim-stakes.

[color=#e39429]1877 — THE ROIL.[/color]  Emberstone seeded the seabeds too. The oceans turned violent — endless magnetic storms, compasses spinning, iron hulls dragged down. Deep water became the wall of the world. Sea trade died; the sky inherited it.

[color=#e39429]1893 — THE PALEWATER DISASTER.[/color]  Scholars learned emberstone holds [i]charge[/i] as well as heat. The first arc-capacitor lit the city of Palewater for six glorious minutes — then burned it to glass in a single night. Arc research was outlawed across the civilized world as "the Devil's spark."

[color=#e39429]1901 — THE COVENANT SCHISM.[/color]  The banned arc-scholars refused to stop. Led by Doctor Cassian Vael, they stole the Palewater shard and vanished into the auroral north. The world forgot them. This was a mistake.

[color=#e39429]1914-1922 — THE FIRST EMBER WAR.[/color]  The new powers finally collided over the ember veins. Eight years of trench lines, land ironclads, and cinder shells — fought almost entirely across the lowland garden-kingdom of [b]Veyre[/b], which had the misfortune of lying between everyone. The war ended in exhaustion, not victory. Veyre was left a poisoned grey waste the survivors call [b]the Ashfall[/b].

[color=#e39429]1938 — THE CRADLE.[/color]  Deep-bore prospectors under dead Veyre struck the impossible: a virgin emberstone field larger than every known vein combined. They named it the Cradle. The news could not be contained.

[color=#e39429]1940 — THE CRADLE WAR.[/color]  Four powers. One motherlode. No treaties left worth the paper. [i]This is where you begin.[/i]


[color=#e39429]═══ EMBERSTONE ═══[/color]

[b]BURNED[/b] — A fist-sized stone fires a boiler for weeks. Powers everything: tanks, trains, forges, cities.
[b]CHARGED[/b] — Holds electrical charge like a battery. The foundation of arc weaponry. Outlawed everywhere except where it isn't.
[b]DUST[/b] — Poison. Ember dust ruins lungs, kills soil, and never washes out. The Ashfall is proof.

Every faction burns it. One faction refuses to — and charges it instead."""
},
1: {
	"title": "KARVATH IRON CONCORD",
	"body": """[color=#e39429]"THE ANVIL OF THE WORLD"[/color]
[i]rust-red and black iron · a hammer over a mountain[/i]
[i]heavy armor, artillery, fortification — the slow hammer[/i]

Before the Fall, the Karvath Massif was a poor country of miners and toolmakers — mocked by the lowland kingdoms as "the people who live in holes." Then the Long Winter came, and the holes were the only warm places left in the world. The mountains held the deepest ember veins anywhere, and ember-fired furnaces kept the mining towns alive while the proud kingdoms below froze in their marble halls. Refugees climbed the passes by the hundred thousand and paid their passage in labor.

Out of that migration the Concord was forged: the mine-barons, the engineers' guilds, and the furnace-priests fused into something that is part state, part company, and part church of iron. Karvath children still memorize the [i]Ledger of the Winter[/i] — the tally of every soul the old kingdoms let starve — and the lesson the Concord took from it is carved over every foundry gate: [color=#e39429][b]"IRON REMEMBERS."[/b][/color] Never again dependent. Never again soft. Everything the Concord builds, it builds twice as thick as it needs to be.

Karvath does not rush. Karvath [i]arrives[/i]. Its land dreadnoughts move at a walking pace behind curtain walls of rolling steel, and its doctrine — [i]the Wall That Walks[/i] — treats war as an engineering problem: establish the line, advance the line, and let the enemy break themselves against it.

The Concord's warmaking voice is [b]Forge-Marshal Odann Kray[/b], a mine-collapse survivor with a pneumatic arm who speaks in short sentences and has never once retreated. Not out of pride, officers say. He simply builds no roads behind him.

[color=#e39429]═══ ARSENAL ═══[/color]
[b]Infantry[/b] — Iron Guard; Boilerplate Grenadiers, steam-armored and slow
[b]Armor[/b] — [b]Bastion[/b] heavy steam tank, the Concord workhorse; [b]Hammerfall[/b] siege mortar crawler, outranges every static defense
[b]Air[/b] — [b]Kondor[/b] armored gunship: slow, heavily plated, Karvath's grudging admission that the sky exists
[b]Support[/b] — [b]Mule[/b] steam hauler
[b]Superunit[/b] — [b]JUGGERNAUT[/b] land dreadnought. A rolling fortress with a crew of thirty and a naval gun. The ground shakes first. Then you see it.
[b]Defenses[/b] — the strongest walls in the war, steam-hammer turrets, mortar pits

[color=#7fd47f]STRONG:[/color] armor, siege range, walls, attrition.
[color=#e35f4f]WEAK:[/color] speed, air cover, cost per unit."""
},
2: {
	"title": "ASHFALL COMPACT",
	"body": """[color=#e39429]"THE MEEK WHO REFUSED"[/color]
[i]olive drab and rust · a green weed growing through a cracked helmet[/i]
[i]cheap numbers, salvage, sabotage — the thousand cuts[/i]

Veyre was the garden of the old world — the lowland kingdom whose wheat fed three continents. Its only crime was geography: it lay flat, fertile, and directly between every power that wanted to strangle the others. When the First Ember War came, it was fought in Veyre's fields, and the great powers' cinder shells salted the earth with ember dust until the garden turned grey. Then they signed their treaty — in a city none of them had wrecked — and went home. Nobody rebuilt Veyre. Nobody thought there was anyone left to rebuild it.

They were wrong. The survivors came up out of the cellars and the flooded trench lines wearing scavenged filter masks, and they got to work. The Compact is not a nation in any way the other powers recognize — it is a web of salvage crews, tunnel families, cellar schools, and militia cells, bound by an oath older than paperwork: [i]no one eats unless everyone eats.[/i] Their first tanks were First-War wrecks winched out of the mud and made to run again. Their parliament is a radio frequency.

The great powers called them rats, and the Compact took the insult as a field manual: rats survive everything, go everywhere, and cannot ever, ever be fully exterminated.

And now the Cradle — the greatest prize in history — has been found [i]directly beneath their homes[/i]. To the Ashfallers this is the final insult arriving on schedule: the thing that murdered Veyre was under its floorboards all along, and here come the fires again.

Their war leader, [b]Warden Mara Sixt[/b], ran a cellar school through the First War before she ever ran a militia, and her standing order carries a teacher's patience: [color=#e39429][b]"Everything the great powers throw away, we throw back."[/b][/color] The Compact does not win battles. It makes battles cost more than they're worth, forever.

[color=#e39429]═══ ARSENAL ═══[/color]
[b]Infantry[/b] — [b]Conscript Militia[/b], the cheapest soldier in the war and the most numerous; Cinder Sappers, gas-masked demolition; [b]Vulture Crews[/b] who strip wrecks for resources — the Compact's signature economy
[b]Armor[/b] — [b]Rat[/b] tankette: tiny, fast, swarming — plus anything they steal from you
[b]Air[/b] — [b]Duster[/b] attack plane, a converted crop-duster with rockets. Ugly, cheap, effective.
[b]Superunit[/b] — [b]THE ASHWORM[/b], an armored war-train that lays its own track. A moving fortress and a moving supply line.
[b]Defenses[/b] — trench networks, barbed wire, minefields, cellar bunkers hidden until they fire

[color=#7fd47f]STRONG:[/color] cost, numbers, salvage economy, dug-in defense.
[color=#e35f4f]WEAK:[/color] low tech ceiling, fragile units, no native heavy armor."""
},
3: {
	"title": "AURELIAN LEAGUE",
	"body": """[color=#e39429]"THE THOUSAND SAILS"[/color]
[i]azure and brass · a gull over a rising sun[/i]
[i]air power, speed, reconnaissance — own the sky[/i]

The Aurel Archipelago was the merchant crossroads of the old world — a league of island principalities grown fat and brilliant on sea trade. The Emberfall spared their cities, and for one gilded decade the Aurelians believed they had escaped history. Then the Roil came, and the sea — their mother, their bank, their entire reason to exist — turned against them. Compasses spun. Iron hulls went down with all hands. Within five years, the greatest navy ever assembled was rusting at anchor.

The League's answer is remembered in a single sentence from Sky-Regent Adora Vantelle's address to the Admiralty in 1879: [color=#e39429][b]"The sea has betrayed us, so we shall marry the sky."[/b][/color]

The merchant houses poured their fortunes into mooring towers, ember-lift airships, and gyro-yards. Cities climbed their own mountains to build sky-harbors above the cloud line. Aurelian territory today is not measured in land — it is measured in [i]routes[/i]: trade lanes, wind corridors, and refueling aeries stitched across the whole map of the world. Half its air fleet is privateers flying under letters of marque, which the League insists is a perfectly respectable arrangement.

Aurelia fights the way it trades: fast, mobile, and allergic to fair exchanges. Its doctrine — [i]Who Holds the Sky Holds the Map[/i] — trades positions instead of blows: scout everything, strike the weak seam, and be gone before the answer arrives.

The current [b]Sky-Regent Lyra Vantelle[/b], great-granddaughter of Adora, was elected at thirty-one after personally leading the relief convoy through the Roil's edge to the starving sky-city of Vell — a feat every rival house called impossible, which is why she did it.

[color=#e39429]═══ ARSENAL ═══[/color]
[b]Infantry[/b] — [b]Sky Marines[/b], glider-dropped shock troops; Rocketeers
[b]Vehicles[/b] — [b]Dart[/b] armored car, very fast and very thin; [b]Zephyr[/b] flak half-track
[b]Air[/b] — [b]Sparrowhawk[/b] biplane fighter, the best dogfighter in the world; [b]Wasp[/b] gyrocopter; [b]Pelican[/b] air transport carrying troops over any terrain
[b]Superunit[/b] — [b]STRATOS LEVIATHAN[/b] carrier zeppelin: a flying airfield launching Sparrowhawk sorties. The League's cities-in-miniature, and its pride.
[b]Defenses[/b] — flak batteries, searchlight towers, tethered mine-balloons

[color=#7fd47f]STRONG:[/color] air supremacy, speed, vision, map control.
[color=#e35f4f]WEAK:[/color] fragile ground forces, expensive losses, weak static defense."""
},
4: {
	"title": "LUMINAR COVENANT",
	"body": """[color=#e39429]"THE SECOND SUN"[/color]
[i]bone-white and arc-violet · a small sun rising over a horizon line[/i]
[i]arc weaponry, energy shields, elite units — few but mighty[/i]

When Palewater burned, the world needed someone to blame, and the arc-scholars were convenient. Laboratories were torched, journals banned, and the study of ember-charge was declared heresy against nature.

The scholars' answer came from Doctor [b]Cassian Vael[/b], the disaster's most brilliant survivor, who stood trial with his burns still bandaged and said only: [color=#e39429][i]"You are angry that we dropped the torch. But you would have us put out the light."[/i][/color] The night before his execution, his students broke him out — and stole the Palewater shard on the way.

The exiles marched north beyond the tree line, where the aurora meets the ice and no sane power would follow. There, around the great shard, they raised [b]Solyn Vaul, the Glass City[/b] — the only city on Earth lit by electric light.

Over forty years the Covenant grew into something between an academy and a faith. Its creed: emberstone is not fuel. It is [i]inheritance[/i] — the frozen light of a dead star — and shoveling it into boilers is desecration. The Covenant does not burn the stone. It [b]charges[/b] it, and with it they built what the world banned: arc lances, capacitor hearts, walls of woven lightning.

The Covenant watched the First Ember War through telescopes, in silence, and made a vow: the world cannot be trusted with the fire. When word of the Cradle broke, the Glass City emptied for the first time in a generation.

Understand this about the white columns advancing behind their shield-domes: they have not come to [i]take[/i] the Cradle. They have come to take it [b]away from everyone[/b]. Archlumen Vael is ancient now, his pulse kept by a clockwork-and-copper heart, his voice arriving by arc-radio like weather: [color=#e39429][b]"We are not your enemy. We are your consequence."[/b][/color]

[color=#e39429]═══ ARSENAL ═══[/color]
[b]Infantry[/b] — [b]Arc Templars[/b], lightning-lance elite who chain damage through grouped enemies; Lance Wardens with personal shield projectors
[b]Vehicles[/b] — [b]Faraday[/b] arc-walker; [b]Glimmer[/b] and [b]Ion Carriage[/b]; [b]Dynamo[/b] generator wagon — Luminar units fight harder inside the grid
[b]Air[/b] — [b]Seraph[/b] rocket-glider interceptor, diving from high altitude
[b]Superunit[/b] — [b]THE CATHEDRAL[/b], a storm-zeppelin that charges the clouds themselves and calls down lightning barrages.
[b]Defenses[/b] — Lightning Spires, Aegis dome projectors — all of it dependent on the power grid

[color=#7fd47f]STRONG:[/color] strongest individual units, shields, chain lightning against swarms.
[color=#e35f4f]WEAK:[/color] tiny armies, everything is expensive, and if the grid falls, the Covenant falls with it."""
},
}


static func page_count() -> int:
	return PAGES.size()
