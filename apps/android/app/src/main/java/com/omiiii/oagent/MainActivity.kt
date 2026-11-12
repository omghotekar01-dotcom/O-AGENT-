package com.omiiii.oagent

import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

private class ControlApi(private val base: String, private val token: String) {
    fun request(path: String, method: String = "GET", body: JSONObject? = null, idempotency: String? = null): JSONObject {
        val cleaned = base.trim().trimEnd('/')
        val localDevelopment = BuildConfig.DEBUG && cleaned.startsWith("http://10.0.2.2:")
        require(cleaned.startsWith("https://") || localDevelopment) {
            "Use HTTPS, or http://10.0.2.2:8787 in the Android debug emulator"
        }
        val connection = URL(cleaned + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 10000
            connection.readTimeout = 15000
            connection.setRequestProperty("Authorization", "Bearer " + token)
            connection.setRequestProperty("Accept", "application/json")
            if (idempotency != null) connection.setRequestProperty("Idempotency-Key", idempotency)
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val stream = if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: "{}"
            val json = JSONObject(text)
            if (connection.responseCode !in 200..299) throw IllegalStateException(json.optString("error", "HTTP ${connection.responseCode}"))
            return json
        } finally { connection.disconnect() }
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { CommandCentre() } }
    }
}

@Composable
private fun CommandCentre() {
    val activity = LocalContext.current as Activity
    var server by remember { mutableStateOf("http://10.0.2.2:8787") }
    var token by remember { mutableStateOf("") }
    var connected by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var state by remember { mutableStateOf<JSONObject?>(null) }
    var selectedWorker by remember { mutableStateOf<String?>(null) }

    fun request(path: String, method: String = "GET", body: JSONObject? = null, key: String? = null) {
        if (loading) return
        loading = true
        thread {
            try {
                val client = ControlApi(server, token)
                if (method != "GET") client.request(path, method, body, key)
                val next = client.request("/api/state")
                activity.runOnUiThread {
                    state = next
                    connected = true
                    error = ""
                    loading = false
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    error = e.message ?: "Request failed"
                    loading = false
                }
            }
        }
    }

    Scaffold(topBar = {
        Surface(tonalElevation = 5.dp) {
            Row(Modifier.fillMaxWidth().padding(18.dp)) {
                Text("✳ O-AGENT", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.weight(1f))
                Text(if (connected) "Connected" else "Disconnected", style = MaterialTheme.typography.labelMedium)
            }
        }
    }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("Your agent command centre", style = MaterialTheme.typography.headlineSmall)
            Text("Live backend state only. No simulated agents or completed tasks.")
            if (!connected) {
                OutlinedTextField(value = server, onValueChange = { server = it }, label = { Text("Backend URL") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = token, onValueChange = { token = it }, label = { Text("Development operator token") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(), singleLine = true)
                Button(onClick = { request("/api/state") }, enabled = token.isNotBlank() && !loading) { Text("Connect") }
                Text("Development-only token authentication. Production login and secure device enrollment are still pending.", style = MaterialTheme.typography.bodySmall)
            } else {
                Row {
                    Button(onClick = { request("/api/state") }, enabled = !loading) { Text("Refresh") }
                    Spacer(Modifier.width(10.dp))
                    OutlinedButton(onClick = {
                        connected = false
                        token = ""
                        state = null
                        selectedWorker = null
                    }) { Text("Disconnect") }
                }
                val workers = state?.optJSONArray("workers")
                val tasks = state?.optJSONArray("tasks")
                Text("Machines (${workers?.length() ?: 0})", style = MaterialTheme.typography.titleLarge)
                if (workers == null || workers.length() == 0) Text("No gateway connected. Run the worker on your laptop.")
                else for (i in 0 until workers.length()) {
                    val machine = workers.getJSONObject(i)
                    val id = machine.optString("id")
                    val online = machine.optString("status") == "online"
                    ElevatedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp)) {
                            Text(machine.optString("name"), style = MaterialTheme.typography.titleMedium)
                            Text("${machine.optString("status")} · ${id}")
                            TextButton(onClick = { selectedWorker = id }, enabled = online) { Text(if (selectedWorker == id) "Selected" else "Select machine") }
                        }
                    }
                }
                Text("Execute work", style = MaterialTheme.typography.titleLarge)
                Text("Target: ${selectedWorker ?: "Select an online machine above"}")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        request("/api/tasks", "POST", JSONObject().put("workerId", selectedWorker).put("kind", "system_info"), java.util.UUID.randomUUID().toString())
                    }, enabled = selectedWorker != null && !loading) { Text("System report") }
                    OutlinedButton(onClick = {
                        request("/api/tasks", "POST", JSONObject().put("workerId", selectedWorker).put("kind", "workspace_inventory"), java.util.UUID.randomUUID().toString())
                    }, enabled = selectedWorker != null && !loading) { Text("List files") }
                }
                Text("Tasks (${tasks?.length() ?: 0})", style = MaterialTheme.typography.titleLarge)
                if (tasks == null || tasks.length() == 0) Text("No tasks submitted.")
                else for (i in 0 until minOf(tasks.length(), 30)) {
                    val task = tasks.getJSONObject(i)
                    val id = task.optString("id")
                    ElevatedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(task.optString("kind"), style = MaterialTheme.typography.titleMedium)
                            Text(task.optString("status") + " · " + task.optString("workerId"))
                            if (task.optString("status") == "waiting_for_approval") {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { request("/api/tasks/$id/decision", "POST", JSONObject().put("approve", true)) }, enabled = !loading) { Text("Approve") }
                                    OutlinedButton(onClick = { request("/api/tasks/$id/decision", "POST", JSONObject().put("approve", false)) }, enabled = !loading) { Text("Reject") }
                                }
                            }
                            if (!task.isNull("result")) Text(task.get("result").toString(), style = MaterialTheme.typography.bodySmall)
                            if (!task.isNull("error")) Text(task.optString("error"), color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
        }
    }
}
