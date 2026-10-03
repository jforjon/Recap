#if DEBUG
import AVFoundation
import Foundation
import SwiftData

/// Screenshot mode. Launch with `-demoMode` and the app runs against an
/// in-memory store seeded with a design-conference library instead of the
/// user's own. Debug builds only — none of this ships.
///
/// Extra launch arguments:
/// - `-demoRecording` — open the capture screen mid-talk
enum DemoMode {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demoMode")
    static let recording = ProcessInfo.processInfo.arguments.contains("-demoRecording")

    /// A live-caption paragraph for the capture screen.
    static let liveTranscript = """
    So the question I keep getting after this talk is, how do you get a design system adopted when nobody asked for it? And honestly, the answer is you don't start with the system. You start with the one screen everybody hates maintaining. For us that was the settings page. Forty-two variants of a toggle row, and not one of them agreed on spacing. So we fixed that one screen, properly, with tokens, and we put the before and after in the engineering channel. That was the whole pitch. No roadmap, no governance deck. Just, look how much code we deleted. And the next week two other teams asked if they could use the row component, and that's the moment it stops being your system and starts being theirs
    """
}

/// Builds the store demo mode runs against: in memory, never synced, seeded
/// with the library below. Everything else — `StorageService` included — runs
/// exactly as it does for real, so screenshots show the real code paths.
enum DemoStore {
    static func makeContainer(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: config) else {
            fatalError("Could not create the demo store")
        }

        let seed = DemoSeed.build()
        let context = ModelContext(container)
        for note in seed.notes {
            let record = NoteRecord(id: note.id, createdAt: ISODate.date(note.createdAt) ?? Date())
            record.projectId = note.projectId
            record.title = note.title
            record.eventName = note.eventName
            record.speakerContext = note.speakerContext
            record.category = note.category?.rawValue
            record.summary = note.summary
            record.transcript = note.transcript
            record.transcriptSegments = note.transcriptSegments
            context.insert(record)
        }
        for project in seed.projects {
            let record = ProjectRecord(id: project.id, name: project.name,
                                       createdAt: ISODate.date(project.createdAt) ?? Date())
            record.notes = project.notes
            record.updatedAt = ISODate.date(project.updatedAt) ?? record.createdAt
            context.insert(record)
        }
        for note in seed.personalNotes {
            let owner: PersonalNoteOwner = note.projectId.map { .project($0) } ?? .recording(note.noteId!)
            context.insert(PersonalNoteRecord(id: note.id, owner: owner, content: note.content,
                                              type: note.type,
                                              createdAt: ISODate.date(note.createdAt) ?? Date()))
        }
        try? context.save()

        DemoSeed.writeSilentAudio(for: seed.audioNotes)
        return container
    }
}

// MARK: - Seed

private enum DemoSeed {
    struct Seed {
        var notes: [Note] = []
        var projects: [Project] = []
        var personalNotes: [PersonalNote] = []
        var audioNotes: [(UUID, Double)] = []
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func date(_ s: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return iso(f.date(from: s)!)
    }

    /// Lays sentences out on a timeline: ~13 characters a second of speech, a
    /// short breath between sentences, and a real pause wherever a paragraph
    /// break (`""`) sits in the list.
    static func segments(_ sentences: [String]) -> [TranscriptSegment] {
        var t = 2.4
        var result: [TranscriptSegment] = []
        for sentence in sentences {
            if sentence.isEmpty { t += 1.8; continue }
            let length = max(1.6, Double(sentence.count) / 13.5)
            result.append(TranscriptSegment(start: t, end: t + length, text: sentence))
            t += length + 0.35
        }
        return result
    }

    static func build() -> Seed {
        var seed = Seed()

        // Projects
        let hatch = id(100), config = id(101), systems = id(102)
        seed.projects = [
            Project(id: hatch, name: "Hatch Conference 2026",
                    notes: hatchProjectSummary,
                    createdAt: date("2026-09-16 08:40"), updatedAt: date("2026-09-18 17:10")),
            Project(id: systems, name: "Design Systems Berlin Meetup",
                    notes: nil,
                    createdAt: date("2026-09-03 18:30"), updatedAt: date("2026-09-10 21:05")),
            Project(id: config, name: "Team research offsite",
                    notes: nil,
                    createdAt: date("2026-08-19 09:00"), updatedAt: date("2026-08-20 16:45")),
        ]

        func note(_ n: Int, project: UUID?, title: String, event: String?, speaker: String?,
                  category: NoteCategory?, when: String, summary: String?,
                  sentences: [String], timed: Bool = true) -> Note {
            let segs = segments(sentences)
            return Note(id: id(n), projectId: project, title: title,
                        eventName: event, speakerContext: speaker, category: category,
                        personalReaction: nil, reactionType: nil, summary: summary,
                        transcript: segs.plainText,
                        transcriptSegments: timed ? segs : nil,
                        createdAt: date(when))
        }

        let trust = note(1, project: hatch,
            title: "Designing for trust in AI products",
            event: "Hatch Conference 2026",
            speaker: "Mara Lindqvist — Principal Product Designer. Opening keynote, main stage, day one.",
            category: .talk, when: "2026-09-16 09:30",
            summary: trustSummary, sentences: trustTranscript)
        seed.notes.append(trust)
        seed.audioNotes.append((trust.id, (trust.transcriptSegments?.last?.end ?? 0) + 4))

        seed.notes.append(note(2, project: hatch,
            title: "The craft is the strategy",
            event: "Hatch Conference 2026",
            speaker: "Tobias Adeyemi — Design Director. Main stage, day one afternoon.",
            category: .talk, when: "2026-09-16 14:15",
            summary: craftSummary, sentences: craftTranscript))

        seed.notes.append(note(3, project: hatch,
            title: "Panel: Where design leadership goes next",
            event: "Hatch Conference 2026",
            speaker: "Moderated by Ines Carvalho. Panellists: Priya Raman (VP Design), Lukas Brenner (Head of Design Ops), Sade Okafor (Founder, independent studio).",
            category: .panel, when: "2026-09-17 11:00",
            summary: nil, sentences: panelTranscript))

        seed.notes.append(note(4, project: hatch,
            title: "Workshop: Critiques that don't hurt",
            event: "Hatch Conference 2026",
            speaker: "Hanna Voss — Design Coach. Half-day workshop, room B.",
            category: .training, when: "2026-09-17 14:00",
            summary: critiqueSummary, sentences: critiqueTranscript))

        seed.notes.append(note(5, project: hatch,
            title: "Accessibility is a design material",
            event: "Hatch Conference 2026",
            speaker: "Jonas Keller — Accessibility Lead. Day two closing talk.",
            category: .talk, when: "2026-09-18 16:20",
            summary: nil, sentences: accessibilityTranscript))

        seed.notes.append(note(6, project: systems,
            title: "Tokens that survive a rebrand",
            event: "Design Systems Berlin Meetup",
            speaker: "Elif Demir — Design Systems Lead.",
            category: .talk, when: "2026-09-10 19:10",
            summary: nil, sentences: tokensTranscript))

        seed.notes.append(note(7, project: systems,
            title: "Lightning talks: component APIs",
            event: "Design Systems Berlin Meetup",
            speaker: "Three five-minute talks.",
            category: .talk, when: "2026-09-03 19:40",
            summary: nil, sentences: Array(tokensTranscript.prefix(10))))

        seed.notes.append(note(8, project: config,
            title: "Synthesis session: onboarding interviews",
            event: "Team research offsite",
            speaker: "Research team, whole-day synthesis.",
            category: .training, when: "2026-08-20 10:00",
            summary: nil, sentences: Array(critiqueTranscript.prefix(12))))

        // Loose recordings — not filed under a project.
        seed.notes.append(note(9, project: nil,
            title: "Hallway chat on research ops",
            event: "Hatch Conference 2026",
            speaker: "Conversation with a research ops lead after the panel.",
            category: nil, when: "2026-09-17 12:10",
            summary: nil, sentences: Array(panelTranscript.suffix(9))))

        seed.notes.append(note(10, project: nil,
            title: "Motion principles for product UI",
            event: "Online webinar",
            speaker: "Ravi Menon — Motion Designer.",
            category: .talk, when: "2026-09-24 17:00",
            summary: nil, sentences: Array(craftTranscript.prefix(14))))

        seed.notes.append(note(11, project: nil,
            title: "Portfolio review practice",
            event: nil, speaker: nil,
            category: .training, when: "2026-09-26 15:30",
            summary: nil, sentences: Array(critiqueTranscript.suffix(8))))

        // Personal notes
        var pn = 200
        func personal(_ content: String, project: UUID? = nil, note: UUID? = nil,
                      type: PersonalNoteType = .text, when: String) {
            pn += 1
            seed.personalNotes.append(PersonalNote(
                id: id(pn), projectId: project, noteId: note,
                content: content, type: type, createdAt: date(when)))
        }

        personal("Steal the \u{201C}show the seams\u{201D} idea for the onboarding flow — confidence labels on imported data.",
                 note: id(1), when: "2026-09-16 09:48")
        personal("She said \u{201C}an undo button is a trust feature\u{201D}. Put that on a slide for Thursday.",
                 note: id(1), when: "2026-09-16 10:02")
        personal("Follow up: ask Mara if the audit template from slide 31 is public.",
                 note: id(1), type: .voice, when: "2026-09-16 10:15")

        personal("Themes so far: trust, craft as leverage, critique culture. Everyone is talking about AI, nobody is talking about undo.",
                 project: hatch, when: "2026-09-16 18:30")
        personal("Book the team a debrief for Monday. 30 min, one takeaway each.",
                 project: hatch, type: .voice, when: "2026-09-17 08:45")
        personal("Best talk of the conference: the trust keynote. Runner-up: the critique workshop.",
                 project: hatch, when: "2026-09-18 18:05")

        personal("Try the \u{201C}I like, I wish, what if\u{201D} format in next Tuesday's crit.",
                 note: id(4), when: "2026-09-17 14:40")
        personal("Rebrand-proof tokens = never name a token after a colour.",
                 project: systems, when: "2026-09-10 20:15")

        return seed
    }

    /// A silent track as long as the transcript, so the player shows up and the
    /// transcript highlights as it plays.
    static func writeSilentAudio(for items: [(UUID, Double)]) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (noteId, seconds) in items {
            let url = directory.appendingPathComponent("\(noteId.uuidString).m4a")
            if FileManager.default.fileExists(atPath: url.path) { continue }
            let sampleRate = 16_000.0
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let file = try? AVAudioFile(forWriting: url, settings: settings),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)
            else { continue }
            buffer.frameLength = 16_000 // zero-filled: one second of silence
            for _ in 0..<Int(seconds.rounded(.up)) {
                try? file.write(from: buffer)
            }
        }
    }

    // MARK: - Content

    static let trustTranscript: [String] = [
        "Good morning, Berlin. It's lovely to open the conference in a room this full of people who care about the details.",
        "I want to talk about trust, and specifically about what happens to trust when a product starts making decisions on your behalf.",
        "",
        "Here's the uncomfortable part. Most AI features I've audited this year fail in exactly the same place.",
        "Not in the model. In the interface around the model.",
        "They present a guess with the same visual confidence as a fact, and the user has no way to tell the difference.",
        "",
        "So the first principle is simple. Show the seams.",
        "If the system is eighty percent sure, the design should look eighty percent sure.",
        "That can be a label, a softer weight, a suggestion chip instead of a filled field. It doesn't have to be a percentage.",
        "People are very good at reading hesitation in a human. We've spent a decade stripping that signal out of our products.",
        "",
        "The second principle: an undo button is a trust feature.",
        "When we added a one-tap revert to our automatic categorisation, usage of the feature went up, not down.",
        "People were willing to let the system act because they knew they could take it back.",
        "Reversibility is what makes delegation feel safe.",
        "",
        "Third, explain the why at the moment of doubt, not in a help centre.",
        "A single line — because you filed three similar receipts under travel — did more for us than any onboarding tour.",
        "",
        "And the last one is the hardest. Let the product say I don't know.",
        "An empty state that admits uncertainty is more trustworthy than a confident wrong answer.",
        "Every time we let the assistant decline, complaints dropped.",
        "",
        "So, to wrap up. Show the seams, make everything reversible, explain at the moment of doubt, and let the product say I don't know.",
        "Trust isn't a brand value you paint on at the end. It's a property of the interaction model. Thank you.",
    ]

    static let trustSummary = """
    ## Key points

    - **Most AI features fail in the interface, not the model** — guesses are shown with the same visual confidence as facts.
    - **Show the seams.** Visual confidence should match system confidence: labels, softer weights, suggestion chips instead of filled fields.
    - **Undo is a trust feature.** Adding one-tap revert to automatic categorisation *increased* usage — reversibility makes delegation feel safe.
    - **Explain at the moment of doubt.** One inline line of reasoning beat any onboarding tour.
    - **Let the product say "I don't know".** Admitting uncertainty reduced complaints.

    ## Takeaways for our team

    1. Audit where the product presents guesses as facts.
    2. Add revert to every automated action.
    3. Replace tooltip explanations with inline reasoning.

    ## Memorable quote

    *“Trust isn't a brand value you paint on at the end. It's a property of the interaction model.”*
    """

    static let craftTranscript: [String] = [
        "I want to start with a slightly provocative claim. Craft is not the opposite of speed. Craft is what lets you go fast later.",
        "Every shortcut you take in a component becomes a tax on every screen that uses it.",
        "",
        "We tracked this for a year. Teams that spent an extra day polishing their primitives shipped features forty percent faster six months on.",
        "Not because they were better designers. Because they stopped re-solving the same problems.",
        "",
        "So when leadership asks why we're spending time on the details, the answer is that the details are the strategy.",
        "Quality compounds. So does its absence.",
        "",
        "Let me show you three examples from our own product.",
        "The first is spacing. We had eleven different values for the gap between a label and its field.",
        "Consolidating that to two took a week and removed hundreds of one-off overrides.",
        "The second is motion. We wrote four principles and deleted every animation that didn't serve one of them.",
        "The third is copy. We treated error messages as a design surface, with the same review as a hero screen.",
        "",
        "None of these are glamorous. All of them changed how the product feels.",
        "And how the product feels is, in the end, the only thing the customer ever experiences.",
    ]

    static let craftSummary = """
    ## Key points

    - **Craft enables speed.** Shortcuts in components become a tax on every screen that uses them.
    - Teams that polished primitives shipped **~40% faster** six months later.
    - **Quality compounds — so does its absence.**

    ## Examples

    - **Spacing:** 11 label-to-field gaps consolidated to 2.
    - **Motion:** four principles; anything not serving one was removed.
    - **Copy:** error messages reviewed like hero screens.
    """

    static let panelTranscript: [String] = [
        "Welcome everyone. Let's jump straight in. Priya, where is design leadership heading in the next few years?",
        "",
        "I think the job is shifting from running a team to running a system. Fewer people, more leverage, and a lot more time spent on how decisions get made.",
        "The leaders I admire are the ones who design the organisation with the same care as the product.",
        "",
        "Lukas, you run design ops. Does that match what you see?",
        "Very much. The unglamorous work — rituals, tooling, how critique happens — is where the leverage is now.",
        "If your critique culture is broken, no amount of talent fixes it.",
        "",
        "Sade, you went independent. What does leadership look like from outside a big org?",
        "Honestly, it looks like taste plus follow-through. Clients don't buy process. They buy judgement they can trust.",
        "",
        "Let's take a question from the audience. Yes, at the front.",
        "How do you keep a research practice alive when budgets get cut?",
        "Make it continuous and small. One conversation a week beats a big study every quarter.",
        "And share raw clips, not reports. A thirty-second clip of a customer struggling changes more minds than a deck.",
        "Put research on the same cadence as shipping, and it stops being the first thing cut.",
    ]

    static let critiqueTranscript: [String] = [
        "Okay, let's get started. Today is about running critiques that make the work better without making people smaller.",
        "First, a quick poll. Hands up if you've left a crit feeling worse about your work and no clearer on what to do next.",
        "Yes. Most of the room. That's what we're fixing.",
        "",
        "Rule one: the presenter sets the frame. What stage is this, and what kind of feedback do you want?",
        "Feedback on visual polish for a sketch is noise. Feedback on flow for a final spec is too late.",
        "",
        "Rule two: critique the work against the goal, not against your taste.",
        "Instead of I don't like the blue, try, I'm not sure the blue makes the primary action obvious.",
        "",
        "Rule three: use a structure. My favourite is I like, I wish, what if.",
        "It forces at least one positive, it separates problems from ideas, and it keeps the loudest person from dominating.",
        "",
        "Let's practise. Get into groups of four. One presenter, three reviewers, ten minutes each.",
        "When you're done, the presenter reads back the three things they'll change. That's the only output that matters.",
        "Good crits end with decisions, not with opinions.",
    ]

    static let critiqueSummary = """
    ## Key points

    - **The presenter sets the frame:** stage of the work and the kind of feedback wanted.
    - **Critique against the goal, not taste.** "I'm not sure the blue makes the primary action obvious" over "I don't like the blue".
    - **Use a structure — *I like, I wish, what if*.** Guarantees a positive, separates problems from ideas, balances voices.
    - **End with decisions:** the presenter reads back three changes.

    ## To try

    - Run the next team crit in groups of four, ten minutes each.
    """

    static let accessibilityTranscript: [String] = [
        "Thanks for staying for the last talk of the day. I'll try to earn it.",
        "I want to reframe accessibility, from a checklist you run at the end to a material you design with from the start.",
        "",
        "When you treat contrast, type size and focus order as constraints from day one, they shape better decisions for everyone.",
        "Captions were built for deaf viewers. Today most video on phones is watched with the sound off.",
        "",
        "So my ask is small. In your next project, write the screen reader script before you draw the screen.",
        "If the flow doesn't make sense read aloud, it probably doesn't make sense at all.",
    ]

    static let tokensTranscript: [String] = [
        "Hi everyone, thanks for having me. I'm going to talk about the rebrand that didn't break our design system.",
        "Two years ago our tokens were named after what they looked like. Blue five hundred, grey one hundred.",
        "Then marketing changed the brand colour, and every one of those names became a lie.",
        "",
        "So we split tokens into two tiers. A palette that describes position on a ramp, and roles that describe meaning.",
        "Screens are only allowed to use roles. Accent, surface, text secondary.",
        "When the brand changed again this spring, we remapped twelve roles and shipped in a day.",
        "",
        "The rule we wrote on the wall: never name a token after a colour.",
        "Name it after the job it does, and the job survives the rebrand.",
        "Questions? Yes, in the back.",
        "Do you version the palette separately from the roles?",
        "We do. The palette changes rarely and loudly. Roles change quietly and often.",
    ]

    static let hatchProjectSummary = """
    ## Themes across Hatch 2026

    - **Trust is an interaction property.** Show the seams, make actions reversible, and let the product admit uncertainty.
    - **Craft is leverage.** Polished primitives make teams faster; quality compounds.
    - **Leadership is system design.** Rituals, critique culture and tooling are where the leverage now sits.
    - **Critique needs structure.** Set the frame, judge against the goal, end with decisions.
    - **Accessibility as a material,** not a final checklist.

    ## What to bring back to the team

    1. Add one-tap undo to every automated action.
    2. Trial *I like, I wish, what if* in the next crit.
    3. Write the screen reader script before drawing the next flow.
    """
}
#endif
