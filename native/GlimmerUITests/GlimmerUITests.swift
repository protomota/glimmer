import XCTest

@MainActor
final class GlimmerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    #if os(macOS)
    func testTodayInlineQuickActionsReceivePointerClicks() {
        let app = makeApp()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
        }
        onboard(app)

        // The toolbar also opens both sheets. A center click on the inline control
        // catches artwork intercepting clicks outside its visible frame.
        let center = CGVector(dx: 0.5, dy: 0.5)
        let energy = app.buttons["today.energy"]
        XCTAssertTrue(energy.waitForExistence(timeout: 5))
        energy.coordinate(withNormalizedOffset: center).click()
        let saveEnergy = app.buttons["Set today’s energy"]
        XCTAssertTrue(saveEnergy.waitForExistence(timeout: 5))
        saveEnergy.click()

        let log = app.buttons["today.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.coordinate(withNormalizedOffset: center).click()
        XCTAssertTrue(app.staticTexts["What did you do?"].waitForExistence(timeout: 5))
        press("Continue", in: app)
        press("Skip tags", in: app)
        let saveLog = app.buttons["saveMoment"]
        XCTAssertTrue(saveLog.waitForExistence(timeout: 5))
        saveLog.click()
        XCTAssertTrue(app.staticTexts["1 logged today"].waitForExistence(timeout: 5))
    }
    #endif

    func testOnboardLogAndRelaunch() throws {
        let app = makeApp()
        app.launch()
        onboard(app)
        capture("Today", app)

        press("Log a moment", in: app)
        press("Continue", in: app)
        press("Short-form video", in: app)
        press("Continue", in: app)
        XCTAssertTrue(app.staticTexts["How did it leave you?"].waitForExistence(timeout: 5))
        capture("Aftertaste dial", app)
        press("saveMoment", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 logged today")).firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 logged today")).firstMatch.waitForExistence(timeout: 5))
        press("Insights", in: app)
        XCTAssertTrue(app.staticTexts["Your first moment"].waitForExistence(timeout: 5))

        press("Today", in: app)
        press("Plan my day", in: app)
        press("Complete Drink some water", in: app)
        XCTAssertTrue(app.staticTexts["1 of 4 complete"].waitForExistence(timeout: 5))
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            let quickAdd = app.textFields["Quick add a task"]
            reveal(quickAdd, in: app, down: true)
            quickAdd.tap()
            quickAdd.typeText("Read a few pages\n")
            XCTAssertTrue(button("Complete Read a few pages", in: app).waitForExistence(timeout: 5))
        }
        #endif
    }

    func testPersonalTodoShowsOnTodayWithoutChangingPlanProgress() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launch()
        press("Plan my day", in: app)
        press("personalTodos.add", in: app)
        let title = app.textFields["personalTodos.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        activate(title)
        title.typeText("Return the library book")
        press("Due date", in: app)
        #if os(iOS)
        if app.keyboards.firstMatch.exists { app.swipeDown(velocity: .slow) }
        #endif
        capture("Personal to-do editor", app)
        press("personalTodos.save", in: app)
        let checkbox = button("Complete Return the library book", in: app)
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        reveal(checkbox, in: app)
        capture("Personal to-dos in Plan", app)
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone { goBack(in: app) }
        #endif
        goTo("Today", in: app)
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        reveal(checkbox, in: app)
        capture("Personal to-dos in Today", app)
        activate(checkbox)
        XCTAssertTrue(app.staticTexts["0 of 4 complete"].exists)
        XCTAssertFalse(checkbox.exists)
    }

    func testToolkitUnloadBreakDownAndOneThing() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launchEnvironment["GLIMMER_UNLOAD_TEXT"] = "Call the dentist|Buy cat food on Friday"
        app.launch()
        press("Plan my day", in: app)

        press("personalTodos.unload", in: app)
        press("unload.sort", in: app)
        XCTAssertTrue(app.buttons["unload.add"].waitForExistence(timeout: 10))
        capture("Unload review", app)
        press("unload.add", in: app)
        XCTAssertTrue(app.buttons["unload.sort"].waitForExistence(timeout: 5), "Unload clears for the next brain dump")
        goBack(in: app)
        let dentist = button("Complete Call the dentist", in: app)
        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        XCTAssertTrue(button("Complete Buy cat food", in: app).exists)

        press("Toolkit for Call the dentist", in: app)
        press("Break it down", in: app)
        let save = app.buttons["breakItDown.save"]
        if !save.waitForExistence(timeout: 10) { press("breakItDown.generate", in: app) }
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["From Glimmer’s offline guide"].exists)
        capture("Break it down", app)
        press("breakItDown.save", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "steps")).firstMatch.waitForExistence(timeout: 5))

        press("Toolkit for Call the dentist", in: app)
        press("One thing", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["oneThing.step"].waitForExistence(timeout: 5))
        capture("One thing", app)
        for _ in 0..<12 where app.buttons["oneThing.done"].exists {
            activate(app.buttons["oneThing.done"])
            pause(0.4)
        }
        XCTAssertTrue(app.staticTexts["That’s one thing finished. Rest, or pick the next."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["oneThing.choice"].exists, "Offers what to do next")
        capture("One thing finished", app)
        press("Close", in: app)
        XCTAssertFalse(button("Complete Call the dentist", in: app).waitForExistence(timeout: 2))
    }

    func testToolkitMessageAndDecisionTools() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launch()
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            press("Plan my day", in: app)
            press("plan.toolkit", in: app)
        } else {
            goTo("Toolkit", in: app)
        }
        #else
        goTo("Toolkit", in: app)
        #endif
        XCTAssertTrue(app.descendants(matching: .any)["toolkit.stepSize"].waitForExistence(timeout: 5))
        capture("Toolkit", app)

        press("toolkit.readTheRoom", in: app)
        type("Per my last email, I still need the slides ASAP. Thanks.", into: app.textViews["room.text"], in: app)
        press("room.read", in: app)
        XCTAssertTrue(app.staticTexts["Urgent"].waitForExistence(timeout: 10))
        capture("Read the room", app)
        goBack(in: app)

        press("toolkit.reword", in: app)
        type("I just wanted to say I really think the draft is done. Sorry it took so long.", into: app.textViews["reword.text"], in: app)
        press("reword.run", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["reword.result"].waitForExistence(timeout: 10))
        capture("Reword", app)
        goBack(in: app)

        press("toolkit.weighIt", in: app)
        type("Should I take the evening pottery class?", into: app.textViews["weigh.decision"], in: app)
        press("weigh.run", in: app)
        XCTAssertTrue(app.buttons["weigh.experiment"].waitForExistence(timeout: 10))
        capture("Weigh it", app)
        press("weigh.experiment", in: app)
    }

    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing text field")
        activate(field)
        field.typeText(text)
        #if os(iOS)
        if app.keyboards.firstMatch.exists { app.swipeDown(velocity: .slow) }
        #endif
    }

    private func expandPractice(in app: XCUIApplication) {
        if !app.buttons["coach.practice"].exists { press("More ways to practice", in: app) }
    }

    func testMomentDisclosureAndCoinReward() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launchEnvironment["GLIMMER_FLOW"] = "log"
        app.launch()
        let people = app.buttons["People"].firstMatch
        XCTAssertTrue(people.waitForExistence(timeout: 8))
        activate(people)
        let option = app.buttons["📞 Called a friend"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        activate(people)
        XCTAssertTrue(option.waitForNonExistence(timeout: 5))
        press("Continue", in: app)
        press("Skip tags", in: app)
        press("saveMoment", in: app)
        let earned = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier == %@ AND label == %@", "earnedCoins", "10 coins earned")).firstMatch
        XCTAssertTrue(earned.waitForExistence(timeout: 5))
        XCTAssertTrue(earned.waitForNonExistence(timeout: 5))
    }

    func testHabitStoneAndMoodSky() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launchEnvironment["GLIMMER_SCREEN"] = "Habits"
        app.launch()

        let sky = app.descendants(matching: .any).matching(identifier: "habits.mood").firstMatch
        XCTAssertTrue(sky.waitForExistence(timeout: 8))
        reveal(sky, in: app)
        XCTAssertEqual(sky.value as? String, "Not set")
        // The sun's last stop sits at the right end of its path.
        let brightest = sky.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.3))
        #if os(macOS)
        brightest.click()
        #else
        brightest.tap()
        #endif
        XCTAssertTrue(sky.waitForValue("Great"))
        capture("Mood sky", app)
        press("Clear today’s mood", in: app)
        XCTAssertTrue(sky.waitForValue("Not set"))

        let stone = app.descendants(matching: .any).matching(identifier: "habit.h1").firstMatch
        XCTAssertTrue(stone.waitForExistence(timeout: 5))
        reveal(stone, in: app)
        XCTAssertEqual(stone.value as? String, "Not done today, 0 of the last 7 days")
        activate(stone)
        let earned = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier == %@ AND label == %@", "earnedCoins", "5 coins earned")).firstMatch
        XCTAssertTrue(earned.waitForExistence(timeout: 5), "Checking off a habit plays the coin celebration")
        XCTAssertEqual(stone.value as? String, "Done today, 1 of the last 7 days")
        capture("Habit stones", app)
        XCTAssertTrue(earned.waitForNonExistence(timeout: 5))
        activate(stone)
        XCTAssertTrue(stone.waitForValue("Not done today, 0 of the last 7 days"))
    }

    func testCoachChatRecommendationsAndFollowUp() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_SCREEN"] = "Coach"
        app.launchEnvironment["GLIMMER_TEST_COACH_GUIDE"] = "1"
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["What’s on your mind?"].waitForExistence(timeout: 8))
        capture("Coach welcome", app)

        press("Help me choose one small practice", in: app)
        let save = app.buttons["Add to today’s plan"].firstMatch
        reveal(save, in: app, down: true)
        // Let the inline card finish scrolling into place before sending the pointer.
        pause(0.45)
        activate(save)
        XCTAssertTrue(app.staticTexts["Saved to today’s plan"].firstMatch.waitForExistence(timeout: 8))
        capture("Coach inline practice saved", app)

        let composer = app.descendants(matching: .any)["coach.question"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        activate(composer)
        composer.typeText("What should I read today?")
        // The composer rides up with the keyboard; let it settle so the send tap lands on the button.
        pause(0.8)
        press("coach.send", in: app)
        if app.staticTexts["What should I read today?"].firstMatch.waitForExistence(timeout: 3) == false {
            pause(0.8)
            press("coach.send", in: app)
        }
        let reading = app.buttons["Read lesson"].firstMatch
        reveal(reading, in: app, down: true)
        capture("Coach lesson follow-up", app)
        activate(reading)
        goBack(in: app)
        press("New chat", in: app)
        XCTAssertTrue(app.staticTexts["What’s on your mind?"].exists)
    }

    func testLifeCoachingPracticeAndWeeklyComparison() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet place to get unstuck"].waitForExistence(timeout: 8))
        capture("Life coach onboarding", app)
        onboard(app)
        goTo("Coach", in: app)
        press("coach.library", in: app)
        expandPractice(in: app)
        press("coach.practice", in: app)
        capture("Work and learning exercises", app)
        let exercise = "See if your manager teaches you"
        press(exercise, in: app)
        XCTAssertFalse(button(exercise, in: app).isEnabled)
        goBack(in: app)
        XCTAssertTrue(app.staticTexts[exercise].waitForExistence(timeout: 6))
        press("Close library", in: app)
        goTo("Weekly", in: app)
        press("weekly.screenTime", in: app)
        XCTAssertTrue(app.staticTexts["Find your weekly total"].waitForExistence(timeout: 6))
        capture("Weekly Screen Time comparison", app)
        goTo("Coach", in: app)
        press("coach.library", in: app)
        expandPractice(in: app)
        XCTAssertTrue(app.staticTexts["Daily Glimmer"].waitForExistence(timeout: 6))
        capture("Daily Glimmer practice", app)
        press("coach.author", in: app)
        XCTAssertTrue(app.staticTexts["Brad Dunlap, author and life coach"].waitForExistence(timeout: 6))
        capture("About this guidance", app)
    }

    func testSpiritualLifeCoachReflection() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet place to get unstuck"].waitForExistence(timeout: 8))
        capture("01 Welcome", app)
        onboard(app)
        let reflection = app.staticTexts["A moment to reflect"]
        reveal(reflection, in: app, down: true)
        capture("02 Reflection on Today", app)
        goTo("Coach", in: app)
        press("coach.library", in: app)
        reveal(app.staticTexts["Today’s reflection"], in: app, down: false)
        capture("03 Coach reflection", app)
        press("coach.reflections", in: app)
        let confidence = app.buttons.matching(NSPredicate(format: "identifier == %@", "practice.practice-one-small-skill")).firstMatch
        reveal(confidence, in: app, down: true)
        capture("04 Confidence practice", app)
        activate(confidence)
        XCTAssertFalse(confidence.isEnabled)
        goBack(in: app)
        expandPractice(in: app)
        press("coach.community", in: app)
        let offer = app.buttons["practice.offer-school-hour"].firstMatch
        reveal(offer, in: app, down: false)
        capture("05 Offer time to a school", app)
        goBack(in: app)
        let signal = app.buttons["coach.signal"]
        reveal(signal, in: app, down: false)
        activate(signal)
        let save = app.buttons["coach.save.try-an-80-20-day"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        capture("06 The 80-20 practice", app)
        activate(save)
        XCTAssertFalse(save.isEnabled)
    }

    func testOnboardingBackKeepsChoices() {
        let app = makeApp()
        app.launch()
        press("onboardingContinue", in: app)
        let labels = ["Spend less time on feeds I regret", "Rebuild my attention span", "Read & learn with more focus"]
        for label in labels { press(label, in: app) }
        for label in labels { XCTAssertTrue(button(label, in: app).isSelected) }
        pause(1)
        capture("Several goals selected", app)
        press("onboardingContinue", in: app)
        XCTAssertTrue(app.staticTexts["What tends to pull you off track?"].waitForExistence(timeout: 5))
        press("onboardingBack", in: app)
        press(labels[1], in: app)
        XCTAssertFalse(button(labels[1], in: app).isSelected)
        press("onboardingBack", in: app)
        press("onboardingContinue", in: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(button(labels[0], in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(button(labels[0], in: app).isSelected)
        XCTAssertFalse(button(labels[1], in: app).isSelected)
        XCTAssertTrue(button(labels[2], in: app).isSelected)
        press(labels[0], in: app)
        press(labels[2], in: app)
        XCTAssertFalse(button("onboardingContinue", in: app).isEnabled)
    }

    func testCompleteOnboardingAndMainRoutes() throws {
        let app = makeApp()
        app.launch()
        press("Continue", in: app)
        XCTAssertFalse(button("onboardingContinue", in: app).isEnabled)
        press("onboardingBack", in: app)
        onboard(app, captureSetup: true)

        for title in ["Today", "Insights", "Weekly", "Coach", "Plan", "Habits", "Challenges", "Lessons", "Cleaning", "Settings"] {
            app.terminate()
            app.launchEnvironment["GLIMMER_SCREEN"] = title
            app.launch()
            XCTAssertFalse(app.staticTexts["A quiet place to get unstuck"].exists)
            pause(0.8)
            capture("Route " + title, app)
        }
        for title in ["Privacy & backups", "Ratings & support"] {
            reveal(app.staticTexts[title].firstMatch, in: app, down: true)
            capture("Settings " + title, app)
        }

        for flow in ["energy", "log"] {
            app.terminate()
            app.launchEnvironment["GLIMMER_SCREEN"] = "Today"
            app.launchEnvironment["GLIMMER_FLOW"] = flow
            app.launch()
            pause(0.8)
            capture("Journal " + flow, app)
        }
        goThroughLog(in: app)
        capture("Journal returning Today", app)
    }

    private func goThroughLog(in app: XCUIApplication) {
        press("Continue", in: app)
        press("Short-form video", in: app)
        press("Continue", in: app)
        capture("Journal aftertaste", app)
        press("saveMoment", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 logged today")).firstMatch.waitForExistence(timeout: 6))
    }

    func testSavedPracticeAndReadyExperimentReview() throws {
        guard let id = ProcessInfo.processInfo.environment["GLIMMER_STAGED_JOURNAL"], UUID(uuidString: id) != nil else {
            throw XCTSkip("This review uses an isolated example journal with seven experiment check-ins.")
        }
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_JOURNAL"] = id
        app.launchEnvironment["GLIMMER_SCREEN"] = "Coach"
        app.launch()
        press("coach.library", in: app)
        press("Start the review", in: app)
        XCTAssertTrue(button("Keep it", in: app).waitForExistence(timeout: 6))
        capture("Experiment review", app)
        app.terminate()
        app.launchEnvironment["GLIMMER_SCREEN"] = "Plan"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT label BEGINSWITH %@ AND NOT label BEGINSWITH %@", "One small skill", "Uncheck", "Complete")).firstMatch
        reveal(row, in: app, down: true)
        activate(row)
        XCTAssertTrue(app.staticTexts["Edit task"].waitForExistence(timeout: 5))
        capture("Existing task editor", app)
    }

    func testWeeklyComparisonAndGuidanceSources() {
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_START_PLAN"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Log a moment"].waitForExistence(timeout: 8))
        let quick = app.buttons["Quick actions"].firstMatch
        if quick.isHittable {
            activate(quick)
            capture("Quick actions", app)
        }
        app.terminate()
        app.launchEnvironment["GLIMMER_SCREEN"] = "Weekly"
        app.launch()
        press("weekly.screenTime", in: app)
        XCTAssertTrue(app.staticTexts["Find your weekly total"].waitForExistence(timeout: 5))
        capture("Weekly Screen Time comparison", app)
        app.terminate()
        app.launchEnvironment["GLIMMER_SCREEN"] = "Coach"
        app.launch()
        press("coach.library", in: app)
        let disclosure = app.buttons["coach.author"].firstMatch
        reveal(disclosure, in: app, down: true)
        pause(0.4)
        activate(disclosure)
        let credit = app.staticTexts["Brad Dunlap, author and life coach"].firstMatch
        reveal(credit, in: app, down: true)
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        capture("About this guidance", app)
    }

    /// Ratings & support offers only free actions: rate, free support, share, feedback and more apps.
    func testSupportRowsAreFree() throws {
        let app = makeApp()
        app.launch()
        onboard(app)
        press("Settings", in: app)
        for row in ["reviewGlimmer", "glimmerSupportTickets"] {
            XCTAssertTrue(button(row, in: app).waitForExistence(timeout: 8), row)
        }
        XCTAssertFalse(app.buttons["glimmerTipJar"].exists)
        #if os(macOS)
        press("glimmerSupportCard", in: app)
        for action in ["feedback", "share", "support", "apps"] {
            XCTAssertTrue(button("support." + action, in: app).waitForExistence(timeout: 8), action)
        }
        XCTAssertFalse(app.buttons["support.tip"].exists)
        capture("Support card", app)
        #else
        reveal(app.buttons["glimmerSupportTickets"], in: app)
        pause(0.6)
        capture("Ratings and support", app)
        #endif
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GLIMMER_TEST_JOURNAL"] = UUID().uuidString
        if let appearance = ProcessInfo.processInfo.environment["GLIMMER_APPEARANCE"] {
            app.launchEnvironment["GLIMMER_APPEARANCE"] = appearance
        }
        return app
    }

    func testReviewScreens() throws {
        let app = makeApp()
        app.launch()
        onboard(app, captureSetup: true)
        capture("01 Today", app)
        press("How’s your energy?", in: app)
        capture("02 Energy check-in", app)
        app.terminate()
        app.launch()
        press("Log a moment", in: app)
        capture("03 Choose input", app)
        press("Continue", in: app)
        capture("04 Describe input", app)
        press("Short-form video", in: app)
        press("Continue", in: app)
        capture("05 Aftertaste dial", app)
        press("saveMoment", in: app)
        for title in ["Insights", "Weekly", "Coach"] {
            press(title, in: app)
            capture("06 \(title)", app)
        }
        app.terminate()
        app.launch()
        press("Plan my day", in: app)
        capture("07 Plan", app)
        press("New scheduled task", in: app)
        capture("08 Task editor", app)
        app.terminate()
        app.launch()
        press("Plan my day", in: app)
        press("Browse the task library", in: app)
        capture("09 Task library", app)
        for title in ["Habits", "Challenges", "Cleaning & maintenance", "Settings"] {
            app.terminate()
            app.launch()
            press(title, in: app)
            capture("10 \(title)", app)
        }
        reveal(app.buttons["glimmerSupportTickets"], in: app)
        capture("11 Ratings and support", app)
    }

    func testDesignReviewDeepScreens() throws {
        let app = makeApp()
        app.launch()
        onboard(app)

        press("Lessons", in: app)
        capture("20 Lessons", app)
        press("Read lesson", in: app)
        capture("21 Lesson reader", app)
        press("Next page", in: app)
        press("Next page", in: app)
        capture("22 Lesson reflection", app)
        press("💬 A reply that changes my mood", in: app)
        press("Next page", in: app)
        press("Next page", in: app)
        press("Next page", in: app)
        capture("23 Lesson takeaway", app)
        press("Complete lesson", in: app)

        relaunch(app)
        press("Challenges", in: app)
        capture("30 Challenges", app)
        press("The One-Item Landing Pad", in: app)
        capture("31 Challenge intro", app)
        press("Get started", in: app)
        capture("32 Challenge lesson", app)
        press("Continue", in: app)
        press("Continue", in: app)
        capture("33 Challenge choice", app)
        press("Keys or wallet", in: app)
        press("Continue", in: app)
        #if !os(macOS)
        app.swipeUp() // Bring the timer above the pinned action bar before tapping it.
        #endif
        press("Start 3-minute timer", in: app)
        capture("34 Challenge timer", app)
        press("I’m done", in: app)
        press("Lighter", in: app)
        capture("35 Challenge complete", app)

        relaunch(app)
        press("Habits", in: app)
        capture("40 Habits today", app)
        press("Month", in: app)
        capture("41 Habits month", app)

        relaunch(app)
        press("Cleaning & maintenance", in: app)
        capture("42 Cleaning", app)
        press("Daily reset", in: app)
        capture("43 Cleaning list", app)

        relaunch(app)
        press("Coach", in: app)
        press("coach.library", in: app)
        press("Design it together", in: app)
        capture("44 Coach experiments", app)

        relaunch(app)
        press("Plan my day", in: app)
        press("New scheduled task", in: app)
        let repeatSwitch = app.switches["Repeat"].firstMatch
        if repeatSwitch.waitForExistence(timeout: 5) {
            #if os(macOS)
            repeatSwitch.click()
            #else
            repeatSwitch.switches.firstMatch.exists ? repeatSwitch.switches.firstMatch.tap() : repeatSwitch.tap()
            #endif
        }
        capture("50 Task editor repeating", app)

        relaunch(app)
        press("Plan my day", in: app)
        press("Plan my day with suggestions", in: app)
        capture("51 Suggestions", app)

        relaunch(app)
        press("Plan my day", in: app)
        press("Browse the task library", in: app)
        press("Easy wins & momentum", in: app)
        capture("52 Library category", app)

        relaunch(app)
        press("Settings", in: app)
        capture("60 Settings", app)
        press("reviewGlimmer", in: app)
        capture("61 Settings support", app)
    }

    /// A paced tour of the logging flow for screen recordings. It taps and drags like a person would.
    func testRecordedTour() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet place to get unstuck"].waitForExistence(timeout: 8))
        pause(1.5)
        // The name field sits below the fold on iPhone; scroll it clear of the action bar first.
        let name = app.textFields.firstMatch
        for _ in 0..<3 where name.frame.maxY > app.buttons["onboardingContinue"].frame.minY { app.swipeUp() }
        type("Alex", into: name, in: app)
        pause(1)
        onboard(app)
        pause(1.5)

        press("Log a moment", in: app)
        pause(1.2)
        press("Apps & sites", in: app)
        pause(1.5)
        press("Add Claude to favorites", in: app)
        pause(1)
        let search = app.textFields["Search or add an app or site"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("gem")
        pause(1.5)
        press("Gemini", in: app)
        pause(1.2)
        press("Activities", in: app)
        pause(1.5)
        press("🧘 Meditated", in: app)
        pause(1.2)
        press("Apps & sites", in: app)
        pause(1.5)
        press("Claude", in: app)
        pause(1.2)
        press("Continue", in: app)
        pause(1)
        press("Coding help", in: app)
        pause(0.8)
        press("Continue", in: app)
        pause(1.2)
        turnDial("Aftertaste", in: app)
        press("More", in: app)
        pause(1)
        press("saveMoment", in: app)
        pause(2.5)

        press("Check in", in: app)
        pause(1.2)
        turnDial("Energy", in: app)
        press("Set today’s energy", in: app)
        pause(2.5)

        press("Plan my day", in: app)
        pause(1)
        let quickAdd = app.textFields["Quick add a task"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5))
        quickAdd.tap()
        quickAdd.typeText("Call the dentist\n")
        pause(2.5)
    }

    /// Run with two isolated review journals installed in the app container.
    func testRecordedScreenTour() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let tour = environment["GLIMMER_TOUR_JOURNAL"],
              let empty = environment["GLIMMER_TOUR_EMPTY_JOURNAL"],
              UUID(uuidString: tour) != nil, UUID(uuidString: empty) != nil, tour != empty else {
            throw XCTSkip("Install the onboarding and empty review journal fixtures to record this tour.")
        }
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        let app = makeApp()
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launchEnvironment["GLIMMER_TEST_JOURNAL"] = tour
        app.launch()
        onboard(app, paced: true)
        holdScreen("Today")
        recordCheckIns(in: app)
        recordReflection(in: app)
        recordPlan(in: app)
        recordWellness(in: app)
        recordLessons(in: app)
        recordSettings(in: app)

        app.terminate()
        app.launchEnvironment["GLIMMER_TEST_JOURNAL"] = empty
        app.launch()
        XCTAssertTrue(app.buttons["Log a moment"].waitForExistence(timeout: 8))
        holdScreen("Empty Today")
        goTo("Insights", in: app)
        XCTAssertTrue(app.staticTexts["What stayed with you today?"].waitForExistence(timeout: 5))
        holdScreen("Empty Insights")
        goTo("Coach", in: app)
        holdScreen("Empty Coach", for: 2.5)
    }

    /// Isolate the long app list when recording the picker on a smaller sheet.
    func testRecordedAppSources() throws {
        guard let journal = ProcessInfo.processInfo.environment["GLIMMER_TOUR_JOURNAL"],
              UUID(uuidString: journal) != nil else {
            throw XCTSkip("Install the review journal fixture to record the app picker.")
        }
        let app = makeApp()
        app.launchEnvironment["GLIMMER_TEST_JOURNAL"] = journal
        app.launchEnvironment["GLIMMER_FLOW"] = "log"
        app.launch()
        press("Apps & sites", in: app)
        showAllAppSources(in: app)
    }

    private func recordCheckIns(in app: XCUIApplication) {
        press("Log a moment", in: app)
        holdScreen("Log source, collapsed")
        press("Apps & sites", in: app)
        holdScreen("Apps and sites, Favorites and Recent")
        showAllAppSources(in: app)
        let search = app.textFields["Search or add an app or site"]
        // The field is above the All section on compact displays.
        reveal(search, in: app, down: false)
        activate(search)
        search.typeText("gem")
        holdScreen("App search")
        press("Gemini", in: app)
        press("Activities", in: app)
        holdScreen("Activities")
        press("🧘 Meditated", in: app)
        press("People", in: app)
        holdScreen("People")
        press("📞 Called a friend", in: app)
        press("Apps & sites", in: app)
        press("Claude", in: app)
        press("Continue", in: app)
        holdScreen("Log tags")
        press("Coding help", in: app)
        press("Continue", in: app)
        holdScreen("Aftertaste")
        turnDial("Aftertaste", in: app)
        // The iPad's form sheet can place these controls under the pinned Save bar.
        scrollTour(in: app, nearEdge: true)
        for decision in ["Less", "Same", "More"] {
            press(decision, in: app)
            holdScreen(decision, for: 0.7)
        }
        press("saveMoment", in: app)
        holdScreen("Log saved with coins", for: 2.8)

        press("How’s your energy?", in: app)
        holdScreen("Energy check-in")
        turnDial("Energy", in: app)
        press("Set today’s energy", in: app)
        holdScreen("Energy saved", for: 2.6)
    }

    private func showAllAppSources(in app: XCUIApplication) {
        scrollTour(in: app, nearEdge: true)
        reveal(app.staticTexts["All"].firstMatch, in: app)
        holdScreen("All apps and sites", for: 2.2)
    }

    private func recordReflection(in app: XCUIApplication) {
        goTo("Insights", in: app)
        holdScreen("Insights")
        scrollTour(in: app)
        holdScreen("Insight charts")
        scrollTour(in: app)
        holdScreen("Platform aftertaste and logs")
        goTo("Weekly", in: app)
        holdScreen("Weekly")
        scrollTour(in: app)
        holdScreen("Weekly patterns and experiments")
        goTo("Coach", in: app)
        holdScreen("Coach")
        press("Start the review", in: app)
        holdScreen("Experiment review")
        scrollTour(in: app)
        holdScreen("Experiment outcomes")
        press("Keep it", in: app)
        holdScreen("Experiment reviewed", for: 2.8)
        press("Design it together", in: app)
        scrollTour(in: app)
        holdScreen("Coach suggestions")
        goTo("Today", in: app)
    }

    private func recordPlan(in app: XCUIApplication) {
        press("Plan my day", in: app)
        holdScreen("Plan")
        press("New scheduled task", in: app)
        scrollTour(in: app)
        let repeatSwitch = app.switches["Repeat"].firstMatch
        reveal(repeatSwitch, in: app)
        let nestedSwitch = repeatSwitch.switches.firstMatch
        let control = nestedSwitch.exists ? nestedSwitch : repeatSwitch
        activate(control)
        XCTAssertFalse(app.buttons["Daily"].exists)
        holdScreen("One-off task editor")
        activate(control)
        scrollTour(in: app)
        press("Weekly", in: app)
        scrollTour(in: app)
        holdScreen("Repeating task editor")
        press("Cancel", in: app)
        press("Plan my day with suggestions", in: app)
        holdScreen("Plan suggestions")
        goBack(in: app)
        press("Browse the task library", in: app)
        holdScreen("Task library")
        press("Easy wins & momentum", in: app)
        holdScreen("Task library category")
        goBack(in: app)
        goBack(in: app)
        leaveTodayDetail(in: app)
    }

    private func recordWellness(in app: XCUIApplication) {
        goTo("Habits", in: app)
        holdScreen("Habits Today")
        press("Month", in: app)
        holdScreen("Habits Month")
        leaveTodayDetail(in: app)

        goTo("Challenges", in: app)
        holdScreen("Challenges")
        press("The One-Item Landing Pad", in: app)
        holdScreen("Challenge introduction")
        press("Get started", in: app)
        for page in ["Challenge lesson one", "Challenge lesson two"] {
            holdScreen(page)
            press("Continue", in: app)
        }
        holdScreen("Challenge choice")
        press("Keys or wallet", in: app)
        press("Continue", in: app)
        holdScreen("Challenge action")
        scrollTour(in: app)
        press("Start 3-minute timer", in: app)
        holdScreen("Challenge timer")
        press("I’m done", in: app)
        holdScreen("Challenge completion")
        press("Lighter", in: app)
        holdScreen("Challenge feedback")
        press("Back to tiny wins", in: app)
        leaveTodayDetail(in: app)

        goTo("Cleaning & maintenance", in: app)
        holdScreen("Cleaning")
        press("Daily reset", in: app)
        holdScreen("Cleaning list")
        goBack(in: app)
        leaveTodayDetail(in: app)
    }

    private func recordLessons(in app: XCUIApplication) {
        goTo("Lessons", in: app)
        holdScreen("Lessons")
        press("Read lesson", in: app)
        holdScreen("Lesson opening")
        press("Next page", in: app)
        holdScreen("Lesson reading")
        press("Next page", in: app)
        holdScreen("Lesson reflection")
        press("💬 A reply that changes my mood", in: app)
        for page in ["Lesson reading, continued", "Lesson practice", "Lesson takeaway"] {
            press("Next page", in: app)
            holdScreen(page)
        }
        press("Complete lesson", in: app)
        holdScreen("Lesson complete")
        leaveTodayDetail(in: app)
    }

    private func recordSettings(in app: XCUIApplication) {
        goTo("Settings", in: app)
        holdScreen("Settings")
        reveal(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Version ")).firstMatch, in: app)
        holdScreen("About Glimmer")
        reveal(app.buttons["glimmerSupportTickets"], in: app)
        holdScreen("Ratings and support", for: 3)
    }

    private func holdScreen(_ title: String, for seconds: TimeInterval = 1.6) {
        XCTContext.runActivity(named: "Recording: \(title)") { _ in pause(seconds) }
    }

    private func scrollTour(in app: XCUIApplication, down: Bool = true, nearEdge: Bool = false) {
        #if os(macOS)
        app.scrollViews.allElementsBoundByIndex.last?.scroll(byDeltaX: 0, deltaY: down ? -370 : 370)
        #else
        let scroll = app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable) ?? app
        if nearEdge {
            // Start outside the dial's drag gesture so the page scrolls.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.80))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.30))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
            return
        }
        if down { scroll.swipeUp(velocity: .slow) } else { scroll.swipeDown(velocity: .slow) }
        #endif
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<4 where !element.isHittable { scrollTour(in: app, down: down) }
        XCTAssertTrue(element.isHittable, "Could not bring the requested control into view", file: file, line: line)
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func goTo(_ title: String, in app: XCUIApplication) {
        let bar = app.tabBars.firstMatch
        if ["Today", "Insights", "Weekly", "Coach"].contains(title), bar.exists {
            let tab = bar.buttons[title].firstMatch
            // When this bar minimizes, its selected tab is the only visible button.
            if !tab.exists, let selected = bar.buttons.allElementsBoundByIndex.first(where: \.isHittable) {
                activate(selected)
                pause(0.4)
            }
            reveal(tab, in: app, down: false)
            activate(tab)
        } else {
            press(title, in: app)
        }
    }

    private func goBack(in app: XCUIApplication) {
        #if os(macOS)
        let toolbarBack = app.toolbars.buttons["Back"].firstMatch
        if toolbarBack.isHittable {
            toolbarBack.click()
            return
        }
        #endif
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "_BackButton", "Back"
        )).firstMatch
        if back.isHittable {
            activate(back)
            return
        }
        let bar = app.navigationBars.allElementsBoundByIndex.last { $0.buttons.firstMatch.exists }
        guard let bar else {
            XCTFail("Could not find the navigation bar's Back button")
            return
        }
        activate(bar.buttons.firstMatch)
    }

    private func leaveTodayDetail(in app: XCUIApplication) {
        if app.tabBars.firstMatch.exists { goBack(in: app) }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Drags the dial's knob up to the top stop, back down to the bottom, and settles near the top.
    private func turnDial(_ label: String, in app: XCUIApplication) {
        let dial = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5), "Missing dial: \(label)")
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { dial.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let top = point(0.5, 0.12), right = point(0.86, 0.45), left = point(0.14, 0.45), high = point(0.8, 0.3)
        for (start, end) in [(top, right), (right, top), (top, left), (left, top), (top, high)] {
            #if os(macOS)
            start.click(forDuration: 0.15, thenDragTo: end, withVelocity: 140, thenHoldForDuration: 0.35)
            #else
            start.press(forDuration: 0.15, thenDragTo: end, withVelocity: 140, thenHoldForDuration: 0.35)
            #endif
            pause(0.5)
        }
        pause(0.8)
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func onboard(_ app: XCUIApplication, captureSetup: Bool = false, paced: Bool = false) {
        let options: [String?] = [
            nil, "Spend less time on feeds I regret", "Short-form video", "Recharged", "Calm",
            "Learn & explain things", nil, "Take a walk", "Gentle & encouraging", "5 seconds, quick taps only",
            "Trade one short-video session for five minutes of something you care about", nil, nil, nil,
        ]
        XCTAssertTrue(app.staticTexts["A quiet place to get unstuck"].waitForExistence(timeout: 8))
        for (index, option) in options.enumerated() {
            if paced { holdScreen("Onboarding \(index + 1) of \(options.count)") }
            if let option { press(option, in: app) }
            if captureSetup { capture(String(format: "Setup %02d", index + 1), app) }
            // XCUITest sometimes drops an element tap on this button (a coordinate tap, like a finger, always lands),
            // so confirm the next page and retry with a centre tap.
            let next = index + 1 < options.count ? app.staticTexts["\(index + 2) of \(options.count)"] : app.buttons["Log a moment"]
            press("onboardingContinue", in: app)
            for _ in 0..<2 where !next.waitForExistence(timeout: 3) {
                app.buttons["onboardingContinue"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
        XCTAssertTrue(app.buttons["Log a moment"].waitForExistence(timeout: 8))
    }

    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let direct = app.buttons.matching(identifier: label).firstMatch
        if direct.exists { return direct }
        let combined = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        if combined.exists { return combined }
        return app.descendants(matching: .any).matching(identifier: label).firstMatch
    }

    private func press(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var target = button(label, in: app)
        // Today uses a lazy grid: off-screen destinations are created only after scrolling.
        for _ in 0..<4 where !target.exists {
            #if os(macOS)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
            #else
            app.swipeUp()
            #endif
            target = button(label, in: app)
        }
        XCTAssertTrue(target.exists || target.waitForExistence(timeout: 7), "Missing control: \(label)", file: file, line: line)
        for _ in 0..<4 where !target.isHittable {
            #if os(macOS)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
            #else
            app.swipeUp()
            #endif
        }
        #if os(macOS)
        target.click()
        #else
        target.tap()
        #endif
    }

    private func capture(_ title: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    /// Waits until the accessibility value reads as the given text.
    func waitForValue(_ text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while value as? String != text, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return value as? String == text
    }
}
