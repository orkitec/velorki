package com.orkitec.velorki.wear

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.RoundaboutRight
import androidx.compose.material.icons.filled.Straight
import androidx.compose.material.icons.filled.TurnLeft
import androidx.compose.material.icons.filled.TurnRight
import androidx.compose.material.icons.filled.TurnSlightLeft
import androidx.compose.material.icons.filled.TurnSlightRight
import androidx.compose.material.icons.filled.UTurnLeft
import androidx.compose.material.icons.filled.UTurnRight
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.CurvedTextStyle
import androidx.wear.compose.foundation.pager.VerticalPager
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.wear.compose.material3.AnimatedPage
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.LocalContentColor
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeText
import androidx.wear.compose.material3.VerticalPageIndicator
import androidx.wear.compose.material3.VerticalPagerScaffold
import androidx.wear.compose.material3.timeTextCurvedText
import androidx.wear.compose.material3.timeTextSeparator
import kotlin.math.sqrt

/** The app's default accent, while the phone has not said. */
private const val DEFAULT_ACCENT = "#C8F542"
private val Secondary = Color(0xFFA6A6A6)
private val Warning = Color(0xFFFF9F0A)

/**
 * The ride on the wrist: one page with the figures, the next turn and the
 * buttons that steer the phone, all without scrolling on the smallest watch,
 * and a second page below it, a turn of the crown away, for the heart rate
 * switch and the footnotes. The Apple app's `RideView.swift`, drawn for
 * round and square Wear OS screens.
 *
 * Every figure on it, and the turn, is formatted and translated by the phone;
 * the screen only sets a figure's unit small.
 */
@Composable
fun RideScreen(state: RideState, session: RideSession) {
    val accent = parseHex(state.context.accent) ?: parseHex(DEFAULT_ACCENT)!!
    val title = when {
        !state.riding -> stringResource(R.string.app_name)
        state.paused -> stringResource(R.string.title_paused)
        else -> stringResource(R.string.title_riding)
    }
    MaterialTheme {
        AppScaffold(
            timeText = {
                // Beside the clock: what the ride is doing, or the app's name.
                TimeText { time ->
                    timeTextCurvedText(title, CurvedTextStyle(color = accent))
                    timeTextSeparator()
                    timeTextCurvedText(time)
                }
            },
        ) {
            val pager = rememberPagerState(pageCount = { 2 })
            VerticalPagerScaffold(
                pagerState = pager,
                pageIndicator = {
                    // Material 3's indicator (1.7.1) on a round screen also
                    // draws a faint stroke of its selected colour outside its
                    // bounds, at the opposite edge, mid-height.
                    VerticalPageIndicator(pagerState = pager, modifier = Modifier.clipToBounds())
                },
            ) {
                VerticalPager(state = pager) { page ->
                    AnimatedPage(pageIndex = page, pagerState = pager) {
                        if (page == 0) {
                            ScreenScaffold { RidePage(state, session, accent) }
                        } else {
                            MorePage(state, session)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Figures at the top, controls at the bottom. The controls never shrink; the
 * figures and the turn do, so the buttons stay on screen on the smallest
 * watch.
 */
@Composable
private fun RidePage(state: RideState, session: RideSession, accent: Color) {
    val round = LocalConfiguration.current.isScreenRound
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = maxWidth
        val height = maxHeight
        val geometry = PageGeometry(width, height, round)
        Column(
            Modifier
                .fillMaxSize()
                .padding(top = geometry.top, bottom = geometry.bottom),
        ) {
            Column(Modifier.padding(horizontal = geometry.side)) {
                if (state.riding) {
                    Figures(state, accent, geometry.figure)
                } else {
                    Heart(state, accent, geometry.figure * 1.3f)
                    Text(
                        stringResource(R.string.start_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = Secondary,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = geometry.side, vertical = 4.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                val problem = state.problem
                if (problem != null) {
                    Fitted(
                        problemText(problem),
                        style = MaterialTheme.typography.bodySmall.copy(color = Warning),
                        maxLines = 4,
                    )
                } else if (state.riding && state.context.turnLabel.isNotEmpty()) {
                    Turn(state.context, geometry.figure)
                }
            }
            Controls(state, session, accent, geometry)
        }
    }
}

/** Where things go on a screen of this size and shape. */
private class PageGeometry(width: Dp, height: Dp, round: Boolean) {
    /** Below the clock, which is set in an arc on either shape. */
    val top: Dp = height * 0.17f

    /** Beside the figures: a round screen is narrower above its middle. */
    val side: Dp = width * (if (round) 0.11f else 0.06f)

    /** The buttons' bottom edge above the screen's. */
    val bottom: Dp = height * (if (round) 0.09f else 0.05f)

    /**
     * Beside the buttons: on a round screen where the circle's chord at
     * their bottom edge ends, on a square one clear of its rounded corners.
     */
    val controlsSide: Dp = if (round) {
        val r = width.value / 2
        val d = r - bottom.value
        (r - sqrt(r * r - d * d) + 2).dp
    } else {
        width * 0.1f
    }

    val controlsHeight: Dp = (height * 0.19f).coerceIn(34.dp, 48.dp)

    /** The figures' size; text scales with the watch, as on the Apple Watch. */
    val figure: TextUnit = (width.value * 0.1f).sp
}

/** Heart rate and speed, distance and time, two by two. */
@Composable
private fun Figures(state: RideState, accent: Color, size: TextUnit) {
    val color = if (state.paused) Secondary else Color.White
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { Heart(state, accent, size) }
            Box(Modifier.weight(1f)) { Figure(state.context.speed, size, color) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { Figure(state.context.distance, size, color) }
            Box(Modifier.weight(1f)) { Figure(state.context.elapsed, size, color) }
        }
    }
}

/**
 * A figure with its unit set small, so four fit side by side at one size.
 * Shrinks rather than cuts.
 */
@Composable
private fun Figure(text: String, size: TextUnit, color: Color = Color.White) {
    val (value, unit) = splitUnit(text)
    Row(verticalAlignment = Alignment.Bottom) {
        Fitted(
            value,
            style = figureStyle(size, color),
            modifier = Modifier.weight(1f, fill = false),
        )
        if (unit != null) {
            Text(
                unit,
                style = MaterialTheme.typography.labelSmall,
                color = Secondary,
                maxLines = 1,
                modifier = Modifier.padding(start = 2.dp, bottom = 2.dp),
            )
        }
    }
}

@Composable
private fun Heart(state: RideState, accent: Color, size: TextUnit) {
    // Beats while measuring; still when paused or idle.
    val beating = state.measuring && !state.paused
    val pulse by rememberInfiniteTransition(label = "heart").animateFloat(
        initialValue = 1f,
        targetValue = if (beating) 0.35f else 1f,
        animationSpec = infiniteRepeatable(tween(600), RepeatMode.Reverse),
        label = "pulse",
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            Icons.Filled.Favorite,
            contentDescription = null,
            tint = if (beating) accent else Secondary,
            modifier = Modifier
                .size((size.value * 0.6f).dp)
                .alpha(if (beating) pulse else 1f),
        )
        Spacer(Modifier.width(3.dp))
        val bpm = state.heartRate
        val color = if (state.paused) Secondary else Color.White
        if (bpm != null) {
            Row(verticalAlignment = Alignment.Bottom) {
                Fitted("$bpm", style = figureStyle(size, color), modifier = Modifier.weight(1f, fill = false))
                Text(
                    stringResource(R.string.bpm),
                    style = MaterialTheme.typography.labelSmall,
                    color = Secondary,
                    maxLines = 1,
                    modifier = Modifier.padding(start = 2.dp, bottom = 2.dp),
                )
            }
        } else {
            Fitted(if (state.measuring) "…" else "--", style = figureStyle(size, Secondary))
        }
    }
}

/** The next turn: how far, then what. Orange while off the route. */
@Composable
private fun Turn(context: RideContext, size: TextUnit) {
    val color = if (context.offRoute) Warning else Color.White
    Row(verticalAlignment = Alignment.CenterVertically) {
        turnIcon(context.turnIcon)?.let { icon ->
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size((size.value * 1.2f).dp))
            Spacer(Modifier.width(6.dp))
        }
        Column {
            if (context.turnDistance.isNotEmpty()) {
                Figure(context.turnDistance, size * 0.85f, color)
            }
            Fitted(
                context.turnLabel,
                style = MaterialTheme.typography.bodySmall.copy(color = color),
                maxLines = 2,
            )
        }
    }
}

@Composable
private fun Controls(state: RideState, session: RideSession, accent: Color, geometry: PageGeometry) {
    val modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = geometry.controlsSide)
        .height(geometry.controlsHeight)
    if (!state.riding) {
        Button(
            onClick = session::start,
            modifier = modifier,
            colors = ButtonDefaults.buttonColors(
                containerColor = accent,
                contentColor = if (isLight(accent)) Color.Black else Color.White,
            ),
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            ButtonLabel(stringResource(R.string.start_ride))
        }
    } else {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val buttonModifier = Modifier
                .weight(1f)
                .height(geometry.controlsHeight)
            if (state.paused) {
                FilledTonalButton(onClick = session::resume, modifier = buttonModifier, contentPadding = PaddingValues(horizontal = 4.dp)) {
                    ButtonLabel(stringResource(R.string.resume))
                }
            } else {
                FilledTonalButton(onClick = session::pause, modifier = buttonModifier, contentPadding = PaddingValues(horizontal = 4.dp)) {
                    ButtonLabel(stringResource(R.string.pause))
                }
            }
            FilledTonalButton(onClick = session::stop, modifier = buttonModifier, contentPadding = PaddingValues(horizontal = 4.dp)) {
                ButtonLabel(stringResource(R.string.finish))
            }
        }
    }
}

/** A button's word, shrunk rather than cut on a narrow watch. */
@Composable
private fun ButtonLabel(text: String) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Fitted(text, style = MaterialTheme.typography.labelMedium.copy(color = LocalContentColor.current))
    }
}

/**
 * The heart rate switch, and what Finish and Battery Saver do: what the
 * rider needs now and then.
 */
@Composable
private fun MorePage(state: RideState, session: RideSession) {
    val round = LocalConfiguration.current.isScreenRound
    val scroll = rememberScrollState()
    ScreenScaffold(scrollState = scroll) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val geometry = PageGeometry(maxWidth, maxHeight, round)
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll)
                    .padding(top = geometry.top, bottom = geometry.top, start = geometry.side, end = geometry.side),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (state.measuring) {
                    FilledTonalButton(onClick = session::stopHeartRate, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.stop_heart_rate))
                    }
                } else if (state.riding && !state.paused) {
                    FilledTonalButton(onClick = session::startHeartRate, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.start_heart_rate))
                    }
                }
                if (state.riding) Footnote(stringResource(R.string.footnote_finish))
                Footnote(stringResource(R.string.footnote_battery))
            }
        }
    }
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = Secondary,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun problemText(problem: Problem): String = when (problem) {
    Problem.HealthAccess -> stringResource(R.string.problem_health_access)
    Problem.PhoneSilent -> stringResource(R.string.problem_phone_silent)
    is Problem.WouldNotStart -> stringResource(R.string.problem_would_not_start, problem.detail)
    is Problem.Stopped -> stringResource(R.string.problem_stopped, problem.detail)
}

/** Text that shrinks to half its size before it is cut. */
@Composable
private fun Fitted(text: String, style: TextStyle, modifier: Modifier = Modifier, maxLines: Int = 1) {
    BasicText(
        text,
        modifier = modifier,
        style = style,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        autoSize = TextAutoSize.StepBased(
            minFontSize = (style.fontSize.value * 0.5f).sp,
            maxFontSize = style.fontSize,
            stepSize = 0.5.sp,
        ),
    )
}

private fun figureStyle(size: TextUnit, color: Color) = TextStyle(
    color = color,
    fontSize = size,
    fontWeight = FontWeight.SemiBold,
    fontFeatureSettings = "tnum",
)

/** The phone's SF Symbol for the turn, drawn with the phone's own Material icon for it. */
fun turnIcon(symbol: String): ImageVector? = when (symbol) {
    "arrow.turn.up.left" -> Icons.Filled.TurnLeft
    "arrow.turn.up.right" -> Icons.Filled.TurnRight
    "arrow.up.left" -> Icons.Filled.TurnSlightLeft
    "arrow.up.right" -> Icons.Filled.TurnSlightRight
    "arrow.uturn.left" -> Icons.Filled.UTurnLeft
    "arrow.uturn.right" -> Icons.Filled.UTurnRight
    "arrow.triangle.turn.up.right.circle" -> Icons.Filled.RoundaboutRight
    "flag.checkered" -> Icons.Filled.Flag
    "arrow.up" -> Icons.Filled.Straight
    "exclamationmark.triangle" -> Icons.Filled.Warning
    else -> null
}

/**
 * "23.8 km/h" as "23.8" and "km/h": the phone's text split at its last space,
 * when what comes before holds a digit and what follows none. Anything else,
 * such as "1:12:05", stays whole.
 */
fun splitUnit(text: String): Pair<String, String?> {
    val space = text.indexOfLast { it.isWhitespace() }
    if (space < 0) return text to null
    val value = text.substring(0, space).trim()
    val unit = text.substring(space + 1)
    if (value.none { it.isDigit() } || unit.isEmpty() || unit.any { it.isDigit() }) return text to null
    return value to unit
}

/** `#RRGGBB` as the phone sends it; null for anything else. */
fun parseHex(hex: String): Color? {
    if (hex.length != 7 || !hex.startsWith("#")) return null
    val rgb = hex.substring(1).toLongOrNull(16) ?: return null
    return Color(0xFF000000 or rgb)
}

/** Whether a colour is light enough to want black text on it. */
fun isLight(color: Color): Boolean =
    (0.299f * color.red + 0.587f * color.green + 0.114f * color.blue) > 0.6f
