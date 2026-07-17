package dev.tuist.hive

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.TextWatcher
import android.text.TextUtils
import android.text.InputType
import android.text.method.LinkMovementMethod
import android.text.style.BackgroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.icu.text.SimpleDateFormat
import android.icu.util.TimeZone
import java.util.concurrent.Executors
import java.util.Locale

class MainActivity : Activity() {
    private enum class Tab { FORAGE, SPECS, DROPS, ACCOUNT }

    private data class SearchEntry(
        val searchableText: String,
        val prominent: Boolean = false,
        val content: () -> View,
    )

    private val client = MobileClient()
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var credentialStore: CredentialStore
    private lateinit var addressInput: EditText
    private lateinit var continueButton: Button
    private lateinit var progress: ProgressBar
    private lateinit var errorText: TextView
    private var pending: PendingAuthorization? = null
    private var session: OAuthSession? = null
    private var user: HiveUser? = null
    private var selectedTab = Tab.FORAGE
    private var showingDetail = false
    private var backAction: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        credentialStore = CredentialStore(this)
        pending = savedInstanceState?.toPendingAuthorization()

        if (intent?.data?.scheme == "dev.tuist.hive") {
            showLogin()
            handleCallback(intent.data)
        } else {
            showLaunch()
            restoreSession()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.data?.scheme == "dev.tuist.hive") {
            if (pending != null) showLogin()
            handleCallback(intent.data)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        pending?.writeTo(outState)
        super.onSaveInstanceState(outState)
    }

    @Deprecated("Uses system back navigation for native detail screens")
    override fun onBackPressed() {
        val action = backAction
        if (action != null) {
            backAction = null
            action()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun showLaunch() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BACKGROUND)
            addView(hiveMark(), centered(width = 72, height = 72, bottom = 20))
            addView(ProgressBar(this@MainActivity), centered(width = 32, height = 32))
            contentDescription = "Launch screen"
        }
        setContentView(root)
    }

    private fun restoreSession() {
        executor.execute {
            try {
                val saved = credentialStore.load()
                if (saved == null) {
                    runOnUiThread(::showLogin)
                    return@execute
                }
                val current = client.currentUser(saved)
                saveSession(current.session)
                user = current.value
                runOnUiThread { showTab(Tab.FORAGE) }
            } catch (_error: Exception) {
                credentialStore.clear()
                session = null
                user = null
                runOnUiThread(::showLogin)
            }
        }
    }

    private fun showLogin() {
        showingDetail = false
        backAction = null
        val title = TextView(this).apply {
            text = "Sign in to Hive"
            textSize = 32f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(FOREGROUND)
        }
        val subtitle = TextView(this).apply {
            text = "Connect to your organization’s Hive deployment."
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(SECONDARY)
        }
        val addressLabel = TextView(this).apply {
            text = "Hive address"
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(FOREGROUND)
        }
        addressInput = EditText(this).apply {
            hint = "https://hive.example.com"
            textSize = 16f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            isSingleLine = true
            setPadding(dp(14), 0, dp(14), 0)
            background = rounded(SURFACE, 12f, BORDER)
            contentDescription = "Hive address"
        }
        errorText = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.rgb(190, 32, 48))
            visibility = View.GONE
            contentDescription = "Sign-in error"
        }
        progress = ProgressBar(this).apply {
            visibility = View.GONE
            isIndeterminate = true
        }
        continueButton = Button(this).apply {
            text = "Continue"
            textSize = 16f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(INDIGO)
            contentDescription = "Continue"
            setOnClickListener { startSignIn() }
        }
        val securityNote = TextView(this).apply {
            text = "Hive opens your browser to sign in securely."
            setCompoundDrawablesWithIntrinsicBounds(android.R.drawable.ic_lock_lock, 0, 0, 0)
            compoundDrawablePadding = dp(8)
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(SECONDARY)
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
            background = rounded(Color.WHITE, 24f, BORDER)
            elevation = dp(10).toFloat()
            addView(addressLabel, matchWidth(bottom = 8))
            addView(addressInput, matchWidth(height = 54, bottom = 14))
            addView(errorText, matchWidth(bottom = 10))
            addView(progress, centered(width = 36, height = 36, bottom = 10))
            addView(continueButton, matchWidth(height = 52, bottom = 16))
            addView(securityNote, matchWidth())
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(56), dp(24), dp(40))
            addView(hiveMark(), centered(width = 72, height = 72, bottom = 28))
            addView(title, matchWidth(bottom = 10))
            addView(subtitle, matchWidth(bottom = 28))
            addView(card, matchWidth())
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(BACKGROUND)
            isFillViewport = true
            addView(content, matchWidth())
        }
        setContentView(scroll)
    }

    private fun startSignIn() {
        val address = addressInput.text.toString()
        if (address.isBlank()) return
        setLoginLoading(true)

        executor.execute {
            try {
                val prepared = client.prepare(address)
                pending = prepared.pending
                runOnUiThread {
                    setLoginLoading(false)
                    hideKeyboard()
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(prepared.url)))
                }
            } catch (error: Exception) {
                runOnUiThread { showLoginError(error) }
            }
        }
    }

    private fun handleCallback(uri: Uri?) {
        if (uri?.scheme != "dev.tuist.hive") return
        val current = pending
        if (current == null) {
            if (session == null) {
                showLoginError(MobileClientException("The sign-in session expired. Please try again."))
            }
            return
        }
        setLoginLoading(true)

        executor.execute {
            try {
                val newSession = client.exchange(uri.toString(), current)
                val currentUser = client.currentUser(newSession)
                saveSession(currentUser.session)
                pending = null
                user = currentUser.value
                runOnUiThread { showTab(Tab.FORAGE) }
            } catch (error: Exception) {
                runOnUiThread { showLoginError(error) }
            }
        }
    }

    private fun showTab(tab: Tab) {
        selectedTab = tab
        showingDetail = false
        backAction = null
        val content = FrameLayout(this).apply {
            setBackgroundColor(BACKGROUND)
        }
        val shell = mainShell(content, tab)
        setContentView(shell)

        when (tab) {
            Tab.FORAGE -> loadForage(content)
            Tab.SPECS -> loadSpecs(content)
            Tab.DROPS -> loadDrops(content)
            Tab.ACCOUNT -> showAccount(content)
        }
    }

    private fun mainShell(content: FrameLayout, selected: Tab): View {
        val navigation = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setBackgroundColor(Color.WHITE)
            elevation = dp(8).toFloat()
        }
        listOf(
            Triple(Tab.FORAGE, "Forage", R.drawable.ic_forage),
            Triple(Tab.SPECS, "Specs", R.drawable.ic_specs),
            Triple(Tab.DROPS, "Drops", R.drawable.ic_drops),
            Triple(Tab.ACCOUNT, "Account", R.drawable.ic_account),
        ).forEach { (tab, label, icon) ->
            val selectedColor = if (tab == selected) INDIGO else SECONDARY
            navigation.addView(
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    isClickable = true
                    isFocusable = true
                    contentDescription = label
                    setOnClickListener { showTab(tab) }
                    addView(FrameLayout(this@MainActivity).apply {
                        addView(ImageView(this@MainActivity).apply {
                            setImageResource(icon)
                            imageTintList = ColorStateList.valueOf(selectedColor)
                        }, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER))
                    }, centered(width = 48, height = 30, bottom = 2))
                    addView(TextView(this@MainActivity).apply {
                        text = label
                        textSize = 12f
                        typeface = if (tab == selected) TEXT_MEDIUM else Typeface.DEFAULT
                        setTextColor(selectedColor)
                    }, centered())
                },
                LinearLayout.LayoutParams(0, dp(66), 1f),
            )
        }

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BACKGROUND)
            addView(content, LinearLayout.LayoutParams(matchParent(), 0, 1f))
            addView(navigation, matchWidth(height = 74))
            contentDescription = "Main navigation"
        }
    }

    private fun loadForage(container: FrameLayout) {
        showLoading(container, "Loading Forage…")
        executor.execute {
            try {
                val result = client.forage(requiredSession())
                saveSession(result.session)
                val items = result.value
                runOnUiThread {
                    if (selectedTab == Tab.FORAGE && !showingDetail) {
                        showForageList(container, items)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread { showContentError(container, "Forage could not load", error) }
            }
        }
    }

    private fun showForageList(container: FrameLayout, items: List<ForageItem>) {
        val list = verticalContent("Forage")
        addSearchableRows(
            list,
            "Search Forage",
            items.map { item ->
                SearchEntry("${item.title} ${item.type} ${item.status}") {
                    row(item.title, "${readable(item.type)}  •  ${readable(item.status)}") {
                        showForageDetail(item)
                    }
                }
            },
            "No forage items",
            "New requests and signals will appear here.",
        )
        replace(container, scroll(list))
    }

    private fun showForageDetail(item: ForageItem) {
        showingDetail = true
        backAction = { showTab(Tab.FORAGE) }
        val content = FrameLayout(this)
        setContentView(mainShell(content, Tab.FORAGE))
        val detail = detailContent(item.title)
        val facts = mutableListOf(
            "Status" to readable(item.status),
            "Type" to readable(item.type),
        )
        item.sourceLabel?.let { facts.add("Source" to it) }
        detail.addView(metadataGroup(facts), matchWidth())
        item.body?.takeIf(String::isNotBlank)?.let {
            detail.addView(sectionTitle("Details"), matchWidth(top = 22, bottom = 8))
            detail.addView(contentCard(bodyText(it)), matchWidth())
        }
        if (item.domains.isNotEmpty()) {
            detail.addView(sectionTitle("Domains"), matchWidth(top = 22, bottom = 8))
            detail.addView(textRows(item.domains.map { it.name }), matchWidth())
        }
        replace(content, scroll(detail))
    }

    private fun loadSpecs(container: FrameLayout) {
        showLoading(container, "Loading Specs…")
        executor.execute {
            try {
                val result = client.specs(requiredSession())
                saveSession(result.session)
                val specs = result.value
                runOnUiThread {
                    if (selectedTab == Tab.SPECS && !showingDetail) showSpecList(container, specs)
                }
            } catch (error: Exception) {
                runOnUiThread { showContentError(container, "Specs could not load", error) }
            }
        }
    }

    private fun showSpecList(container: FrameLayout, specs: List<HiveSpec>) {
        val list = verticalContent("Specs")
        addSearchableRows(
            list,
            "Search Specs",
            specs.map { spec ->
                val activity = if (spec.hasNewActivity) "  •  New activity" else ""
                SearchEntry("${spec.number} ${spec.title} ${spec.status}") {
                    row("#${spec.number}  ${spec.title}", readable(spec.status) + activity) {
                        showSpecDetail(spec)
                    }
                }
            },
            "No specs",
            "Product proposals will appear here.",
        )
        replace(container, scroll(list))
    }

    private fun showSpecDetail(spec: HiveSpec) {
        showingDetail = true
        backAction = { showTab(Tab.SPECS) }
        val content = FrameLayout(this)
        setContentView(mainShell(content, Tab.SPECS))
        val detail = detailContent("#${spec.number} ${spec.title}")
        detail.addView(
            metadataGroup(
                listOf(
                    "Status" to readable(spec.status),
                    "Visibility" to readable(spec.visibility),
                    "Revision" to spec.revision.toString(),
                ),
            ),
            matchWidth(),
        )
        spec.summary?.takeIf(String::isNotBlank)?.let {
            detail.addView(sectionTitle("Summary"), matchWidth(top = 22, bottom = 8))
            detail.addView(contentCard(bodyText(it)), matchWidth())
        }
        detail.addView(sectionTitle("Proposal"), matchWidth(top = 22, bottom = 8))
        detail.addView(contentCard(markdownText(spec.body)), matchWidth())
        if (spec.domains.isNotEmpty()) {
            detail.addView(sectionTitle("Domains"), matchWidth(top = 22, bottom = 8))
            detail.addView(textRows(spec.domains.map { it.name }), matchWidth())
        }
        replace(content, scroll(detail))
    }

    private fun loadDrops(container: FrameLayout) {
        showLoading(container, "Loading Drops…")
        executor.execute {
            try {
                val result = client.drops(requiredSession())
                saveSession(result.session)
                val drops = result.value
                runOnUiThread {
                    if (selectedTab == Tab.DROPS && !showingDetail) showDropList(container, drops)
                }
            } catch (error: Exception) {
                runOnUiThread { showContentError(container, "Drops could not load", error) }
            }
        }
    }

    private fun showDropList(container: FrameLayout, drops: List<HiveDrop>) {
        val list = verticalContent("Drops")
        val digest = SearchEntry("Weekly digests narrated editions shipped updates", true) {
            row(
                "Weekly digests",
                "Narrated editions connecting each week’s shipped updates",
                prominent = true,
            ) { showDropDigests() }
        }
        addSearchableRows(
            list,
            "Search Drops",
            listOf(digest) + drops.map { drop ->
                val version = drop.version?.let { "  •  $it" }.orEmpty()
                SearchEntry("${drop.number} ${drop.title} ${drop.sourceType} ${drop.version.orEmpty()}") {
                    row("#${drop.number}  ${drop.title}", readable(drop.sourceType) + version) {
                        showDropDetail(drop)
                    }
                }
            },
            "No drops",
            "Shipped updates will appear here.",
        )
        replace(container, scroll(list))
    }

    private fun showDropDetail(drop: HiveDrop) {
        showingDetail = true
        backAction = { showTab(Tab.DROPS) }
        val content = FrameLayout(this)
        setContentView(mainShell(content, Tab.DROPS))
        val detail = detailContent("#${drop.number} ${drop.title}")
        val facts = mutableListOf("Source" to readable(drop.sourceType))
        drop.version?.let { facts.add("Version" to it) }
        drop.publishedAt?.let { facts.add("Published" to published(it)) }
        detail.addView(metadataGroup(facts), matchWidth())
        drop.body?.takeIf(String::isNotBlank)?.let {
            detail.addView(sectionTitle("Update"), matchWidth(top = 22, bottom = 8))
            detail.addView(contentCard(markdownText(it)), matchWidth())
        }
        if (drop.domains.isNotEmpty()) {
            detail.addView(sectionTitle("Domains"), matchWidth(top = 22, bottom = 8))
            detail.addView(textRows(drop.domains.map { it.name }), matchWidth())
        }
        detail.addView(
            actionButton("Open original") {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(drop.url)))
            },
            matchWidth(height = 48, top = 22),
        )
        replace(content, scroll(detail))
    }

    private fun showDropDigests() {
        showingDetail = true
        backAction = { showTab(Tab.DROPS) }
        val content = FrameLayout(this)
        setContentView(mainShell(content, Tab.DROPS))
        showLoading(content, "Loading weekly digests…")
        executor.execute {
            try {
                val result = client.dropDigests(requiredSession())
                saveSession(result.session)
                val digests = result.value
                runOnUiThread {
                    if (selectedTab == Tab.DROPS && showingDetail) {
                        showDropDigestList(content, digests)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread { showContentError(content, "Weekly digests could not load", error) }
            }
        }
    }

    private fun showDropDigestList(container: FrameLayout, digests: List<DropDigest>) {
        val list = detailContent("Weekly digests")
        addSearchableRows(
            list,
            "Search Digests",
            digests.map { digest ->
                SearchEntry("${digest.title} ${digest.weekStart} ${digest.weekEnd}") {
                    row(
                        digest.title,
                        "${weekRange(digest.weekStart, digest.weekEnd)}  •  ${digest.dropCount} Drops",
                    ) { showDropDigestDetail(digest) }
                }
            },
            "No weekly digests",
            "Narrated editions will appear here.",
        )
        replace(container, scroll(list))
    }

    private fun showDropDigestDetail(digest: DropDigest) {
        showingDetail = true
        backAction = { showDropDigests() }
        val content = FrameLayout(this)
        setContentView(mainShell(content, Tab.DROPS))
        val detail = detailContent(digest.title)
        detail.addView(
            metadataGroup(
                listOf(
                    "Week" to weekRange(digest.weekStart, digest.weekEnd),
                    "Drops" to digest.dropCount.toString(),
                    "Published" to published(digest.publishedAt),
                ),
            ),
            matchWidth(),
        )
        detail.addView(sectionTitle("Summary"), matchWidth(top = 22, bottom = 8))
        detail.addView(contentCard(bodyText(digest.summary)), matchWidth())
        detail.addView(sectionTitle("Edition"), matchWidth(top = 22, bottom = 8))
        detail.addView(contentCard(markdownText(digest.body)), matchWidth())
        replace(content, scroll(detail))
    }

    private fun showAccount(container: FrameLayout) {
        val content = verticalContent("Account")
        val currentUser = user
        val currentSession = session
        if (currentUser != null && currentSession != null) {
            content.addView(
                metadataGroup(
                    listOf(
                        "Email" to currentUser.email,
                        "Role" to readable(currentUser.role),
                        "Hive" to client.server(currentSession),
                    ),
                ),
                matchWidth(),
            )
        }
        content.addView(
            actionButton("Sign out", destructive = true, onClick = ::signOut),
            matchWidth(height = 48, top = 22),
        )
        replace(container, scroll(content))
    }

    private fun signOut() {
        showLaunch()
        executor.execute {
            session?.let { runCatching { client.signOut(it) } }
            credentialStore.clear()
            session = null
            user = null
            runOnUiThread(::showLogin)
        }
    }

    private fun requiredSession(): OAuthSession =
        session ?: throw MobileClientException("The sign-in session is missing.")

    private fun saveSession(updated: OAuthSession) {
        credentialStore.save(updated)
        session = updated
    }

    private fun showLoading(container: FrameLayout, label: String) {
        replace(container, LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            addView(ProgressBar(this@MainActivity), centered(width = 36, height = 36, bottom = 12))
            addView(bodyText(label), centered())
        })
    }

    private fun showContentError(container: FrameLayout, title: String, error: Exception) {
        replace(container, emptyState(title, error.message ?: "Try again."))
    }

    private fun verticalContent(title: String): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(20), dp(20), dp(32))
        setBackgroundColor(BACKGROUND)
        addView(TextView(this@MainActivity).apply {
            text = title
            textSize = 28f
            typeface = TEXT_MEDIUM
            setTextColor(FOREGROUND)
        }, matchWidth(bottom = 16))
    }

    private fun detailContent(title: String): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(12), dp(20), dp(32))
        setBackgroundColor(BACKGROUND)
        addView(LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(FrameLayout(this@MainActivity).apply {
                foreground = RippleDrawable(
                    ColorStateList.valueOf(Color.argb(28, 91, 74, 232)),
                    null,
                    rounded(Color.WHITE, 22f),
                )
                isClickable = true
                isFocusable = true
                contentDescription = "Back"
                setOnClickListener { navigateBack() }
                addView(ImageView(this@MainActivity).apply {
                    setImageResource(R.drawable.ic_chevron_left)
                    imageTintList = ColorStateList.valueOf(INDIGO)
                }, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER))
            }, LinearLayout.LayoutParams(dp(44), dp(44)))
            addView(TextView(this@MainActivity).apply {
                text = title
                textSize = 22f
                typeface = TEXT_MEDIUM
                setTextColor(FOREGROUND)
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, wrapContent(), 1f).apply {
                marginStart = dp(4)
            })
        }, matchWidth(bottom = 14))
    }

    private fun navigateBack() {
        val action = backAction ?: return
        backAction = null
        action()
    }

    private fun addSearchableRows(
        content: LinearLayout,
        hint: String,
        entries: List<SearchEntry>,
        emptyTitle: String,
        emptyDescription: String,
    ) {
        val results = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val search = searchField(hint)

        fun render(query: String) {
            results.removeAllViews()
            val normalized = query.trim().lowercase()
            val visible = entries.filter {
                normalized.isEmpty() || it.searchableText.lowercase().contains(normalized)
            }
            if (visible.isEmpty()) {
                val title = if (entries.isEmpty()) emptyTitle else "No matches"
                val description = if (entries.isEmpty()) emptyDescription else "Try a different search."
                results.addView(emptyState(title, description), matchWidth())
            } else {
                visible.filter(SearchEntry::prominent).forEach { entry ->
                    results.addView(entry.content(), matchWidth(bottom = 12))
                }

                val regular = visible.filterNot(SearchEntry::prominent)
                if (regular.isNotEmpty()) {
                    results.addView(groupedRows(regular), matchWidth())
                }
            }
        }

        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                render(value?.toString().orEmpty())
            }
            override fun afterTextChanged(value: Editable?) = Unit
        })
        content.addView(search, matchWidth(height = 48, bottom = 12))
        content.addView(results, matchWidth())
        render("")
    }

    private fun groupedRows(entries: List<SearchEntry>): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = rounded(Color.WHITE, 16f)
        clipToOutline = true
        entries.forEachIndexed { index, entry ->
            addView(entry.content(), matchWidth())
            if (index < entries.lastIndex) addView(divider(), matchWidth(height = 1))
        }
    }

    private fun divider(): View = View(this).apply {
        setBackgroundColor(DIVIDER)
    }

    private fun searchField(hint: String): EditText = EditText(this).apply {
        this.hint = hint
        textSize = 15f
        inputType = InputType.TYPE_CLASS_TEXT
        isSingleLine = true
        setTextColor(FOREGROUND)
        setHintTextColor(SECONDARY)
        setPadding(dp(16), 0, dp(16), 0)
        setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
        compoundDrawablePadding = dp(10)
        compoundDrawableTintList = ColorStateList.valueOf(SECONDARY)
        background = rounded(SEARCH_SURFACE, 14f)
        contentDescription = hint
    }

    private fun row(
        title: String,
        subtitle: String,
        prominent: Boolean = false,
        onClick: () -> Unit,
    ): View {
        val ripple = ColorStateList.valueOf(Color.argb(28, 91, 74, 232))
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(12), dp(14))
            background = if (prominent) rounded(FEATURED_SURFACE, 16f) else null
            foreground = RippleDrawable(
                ripple,
                null,
                rounded(Color.WHITE, if (prominent) 16f else 0f),
            )
            isClickable = true
            isFocusable = true
            setOnClickListener { onClick() }
            minimumHeight = dp(68)
            contentDescription = "$title. $subtitle"
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(this@MainActivity).apply {
                    text = title
                    textSize = 15f
                    typeface = TEXT_MEDIUM
                    setTextColor(FOREGROUND)
                }, matchWidth(bottom = 5))
                addView(TextView(this@MainActivity).apply {
                    text = subtitle
                    textSize = 13f
                    setTextColor(SECONDARY)
                }, matchWidth())
            }, LinearLayout.LayoutParams(0, wrapContent(), 1f))
            addView(ImageView(this@MainActivity).apply {
                setImageResource(R.drawable.ic_chevron_right)
                imageTintList = ColorStateList.valueOf(if (prominent) INDIGO else TERTIARY)
                scaleType = ImageView.ScaleType.CENTER
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(28), dp(28)))
        }
        return card
    }

    private fun metadata(label: String, value: String): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(13), dp(16), dp(13))
        addView(bodyText(label).apply { setTextColor(SECONDARY) }, LinearLayout.LayoutParams(0, wrapContent(), 1f))
        addView(bodyText(value).apply { gravity = Gravity.END }, LinearLayout.LayoutParams(0, wrapContent(), 2f))
    }

    private fun metadataGroup(items: List<Pair<String, String>>): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = rounded(Color.WHITE, 16f)
        clipToOutline = true
        items.forEachIndexed { index, (label, value) ->
            addView(metadata(label, value), matchWidth())
            if (index < items.lastIndex) addView(divider(), matchWidth(height = 1))
        }
    }

    private fun textRows(values: List<String>): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = rounded(Color.WHITE, 16f)
        clipToOutline = true
        values.forEachIndexed { index, value ->
            addView(bodyText(value).apply {
                setPadding(dp(16), dp(13), dp(16), dp(13))
            }, matchWidth())
            if (index < values.lastIndex) addView(divider(), matchWidth(height = 1))
        }
    }

    private fun contentCard(content: View): View = FrameLayout(this).apply {
        background = rounded(Color.WHITE, 16f)
        setPadding(dp(16), dp(16), dp(16), dp(16))
        addView(content, FrameLayout.LayoutParams(matchParent(), wrapContent()))
    }

    private fun actionButton(
        label: String,
        destructive: Boolean = false,
        onClick: () -> Unit,
    ): View = TextView(this).apply {
        text = label
        textSize = 15f
        typeface = TEXT_MEDIUM
        gravity = Gravity.CENTER
        setTextColor(if (destructive) DESTRUCTIVE else Color.WHITE)
        background = rounded(if (destructive) Color.WHITE else INDIGO, 12f)
        foreground = RippleDrawable(
            ColorStateList.valueOf(Color.argb(32, 255, 255, 255)),
            null,
            rounded(Color.WHITE, 12f),
        )
        isClickable = true
        isFocusable = true
        contentDescription = label
        setOnClickListener { onClick() }
    }

    private fun sectionTitle(value: String): TextView = TextView(this).apply {
        text = value.uppercase()
        textSize = 12f
        typeface = TEXT_MEDIUM
        setTextColor(SECONDARY)
        letterSpacing = 0.04f
    }

    private fun bodyText(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 15f
        setTextColor(FOREGROUND)
        setLineSpacing(0f, 1.18f)
    }

    private fun markdownText(source: String): TextView = bodyText("").apply {
        text = renderMarkdown(source)
        setTextIsSelectable(true)
        movementMethod = LinkMovementMethod.getInstance()
        contentDescription = "Markdown content"
    }

    private fun renderMarkdown(source: String): SpannableStringBuilder {
        val output = SpannableStringBuilder()
        val lines = source.lines()
        var index = 0

        while (index < lines.size) {
            val line = lines[index].trim()
            if (line.isEmpty()) {
                index += 1
                continue
            }

            val heading = MARKDOWN_HEADING.matchEntire(line)
            if (heading != null) {
                val start = output.length
                appendInlineMarkdown(output, heading.groupValues[2])
                output.setSpan(
                    StyleSpan(Typeface.BOLD),
                    start,
                    output.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                output.setSpan(
                    RelativeSizeSpan(if (heading.groupValues[1].length == 1) 1.5f else 1.2f),
                    start,
                    output.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                output.append("\n\n")
                index += 1
                continue
            }

            val listItem = markdownListItem(line)
            if (listItem != null) {
                val ordered = listItem.first
                var listIndex = 1
                while (index < lines.size) {
                    val item = markdownListItem(lines[index].trim()) ?: break
                    if (item.first != ordered) break
                    output.append(if (ordered) "${listIndex++}.  " else "•  ")
                    appendInlineMarkdown(output, item.second)
                    output.append('\n')
                    index += 1
                }
                output.append('\n')
                continue
            }

            val paragraph = mutableListOf(line)
            index += 1
            while (index < lines.size) {
                val next = lines[index].trim()
                if (next.isEmpty() || MARKDOWN_HEADING.matches(next) || markdownListItem(next) != null) break
                paragraph.add(next)
                index += 1
            }
            appendInlineMarkdown(output, paragraph.joinToString(" "))
            output.append("\n\n")
        }

        while (output.endsWith("\n")) output.delete(output.length - 1, output.length)
        return output
    }

    private fun markdownListItem(line: String): Pair<Boolean, String>? {
        MARKDOWN_UNORDERED.matchEntire(line)?.let { return false to it.groupValues[1] }
        MARKDOWN_ORDERED.matchEntire(line)?.let { return true to it.groupValues[1] }
        return null
    }

    private fun appendInlineMarkdown(output: SpannableStringBuilder, source: String) {
        var cursor = 0
        MARKDOWN_INLINE.findAll(source).forEach { match ->
            output.append(source, cursor, match.range.first)
            val start = output.length
            val value = match.groupValues.drop(1).first { it.isNotEmpty() }
            output.append(value)
            val span = when {
                match.groupValues[1].isNotEmpty() -> URLSpan(match.groupValues[2])
                match.groupValues[3].isNotEmpty() -> StyleSpan(Typeface.BOLD)
                match.groupValues[4].isNotEmpty() -> TypefaceSpan("monospace")
                else -> StyleSpan(Typeface.ITALIC)
            }
            output.setSpan(span, start, output.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (match.groupValues[4].isNotEmpty()) {
                output.setSpan(
                    BackgroundColorSpan(ACTIVE_INDICATOR),
                    start,
                    output.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
            cursor = match.range.last + 1
        }
        output.append(source, cursor, source.length)
    }

    private fun emptyState(title: String, description: String): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(dp(28), dp(72), dp(28), dp(28))
        addView(TextView(this@MainActivity).apply {
            text = title
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(FOREGROUND)
        }, matchWidth(bottom = 8))
        addView(TextView(this@MainActivity).apply {
            text = description
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(SECONDARY)
        }, matchWidth())
    }

    private fun scroll(content: View): ScrollView = ScrollView(this).apply {
        setBackgroundColor(BACKGROUND)
        addView(content, matchWidth())
    }

    private fun replace(container: FrameLayout, content: View) {
        container.removeAllViews()
        container.addView(content, FrameLayout.LayoutParams(matchParent(), matchParent()))
    }

    private fun hiveMark(): TextView = TextView(this).apply {
        text = "H"
        textSize = 30f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        background = rounded(INDIGO, 22f)
        contentDescription = "Hive"
    }

    private fun setLoginLoading(loading: Boolean) {
        continueButton.isEnabled = !loading
        continueButton.text = if (loading) "Connecting…" else "Continue"
        progress.visibility = if (loading) View.VISIBLE else View.GONE
        if (loading) errorText.visibility = View.GONE
    }

    private fun showLoginError(error: Exception) {
        setLoginLoading(false)
        errorText.text = error.message ?: "Sign-in failed."
        errorText.visibility = View.VISIBLE
    }

    private fun hideKeyboard() {
        getSystemService(InputMethodManager::class.java)
            .hideSoftInputFromWindow(addressInput.windowToken, 0)
    }

    private fun readable(value: String): String = when (value.lowercase()) {
        "github", "github_release" -> "GitHub Release"
        "rss" -> "RSS"
        else -> value.replace('_', ' ').split(' ').joinToString(" ") { word ->
            word.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
    }

    private fun published(value: String): String = runCatching {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val output = SimpleDateFormat("MMM d, yyyy · HH:mm 'UTC'", Locale.getDefault()).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        output.format(requireNotNull(input.parse(value)))
    }.getOrDefault(value)

    private fun weekRange(start: String, end: String): String = runCatching {
        val input = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val startOutput = SimpleDateFormat("MMM d", Locale.getDefault())
        val endOutput = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
        "${startOutput.format(requireNotNull(input.parse(start)))} – ${
            endOutput.format(requireNotNull(input.parse(end)))
        }"
    }.getOrDefault("$start – $end")

    private fun rounded(fill: Int, radius: Float, stroke: Int? = null): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            color = ColorStateList.valueOf(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

    private fun matchWidth(height: Int? = null, top: Int = 0, bottom: Int = 0) =
        LinearLayout.LayoutParams(
            matchParent(),
            height?.let(::dp) ?: wrapContent(),
        ).apply {
            topMargin = dp(top)
            bottomMargin = dp(bottom)
        }

    private fun centered(width: Int? = null, height: Int? = null, bottom: Int = 0) =
        LinearLayout.LayoutParams(
            width?.let(::dp) ?: wrapContent(),
            height?.let(::dp) ?: wrapContent(),
        ).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            bottomMargin = dp(bottom)
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun matchParent(): Int = ViewGroup.LayoutParams.MATCH_PARENT
    private fun wrapContent(): Int = ViewGroup.LayoutParams.WRAP_CONTENT

    companion object {
        private val TEXT_MEDIUM = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        private val INDIGO = Color.rgb(91, 74, 232)
        private val BACKGROUND = Color.rgb(247, 247, 251)
        private val ACTIVE_INDICATOR = Color.rgb(226, 222, 255)
        private val SURFACE = Color.rgb(248, 247, 252)
        private val FEATURED_SURFACE = Color.rgb(239, 237, 255)
        private val SEARCH_SURFACE = Color.rgb(235, 235, 241)
        private val BORDER = Color.rgb(215, 211, 226)
        private val DIVIDER = Color.rgb(231, 230, 236)
        private val FOREGROUND = Color.rgb(28, 26, 38)
        private val SECONDARY = Color.rgb(100, 96, 116)
        private val TERTIARY = Color.rgb(156, 152, 166)
        private val DESTRUCTIVE = Color.rgb(190, 32, 48)
        private val MARKDOWN_HEADING = Regex("^(#{1,6})\\s+(.+)$")
        private val MARKDOWN_UNORDERED = Regex("^[-*]\\s+(.+)$")
        private val MARKDOWN_ORDERED = Regex("^\\d+\\.\\s+(.+)$")
        private val MARKDOWN_INLINE = Regex(
            "\\[([^]]+)]\\(([^)]+)\\)|\\*\\*([^*]+)\\*\\*|`([^`]+)`|[*_]([^*_]+)[*_]",
        )
    }
}

private fun PendingAuthorization.writeTo(bundle: Bundle) {
    bundle.putString("pending", raw)
}

private fun Bundle.toPendingAuthorization(): PendingAuthorization? {
    return getString("pending")?.let(::PendingAuthorization)
}
