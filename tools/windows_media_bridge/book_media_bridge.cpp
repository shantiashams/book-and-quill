#include "book_media_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <exception>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSession;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;
using winrt::Windows::Storage::Streams::DataReader;
using winrt::Windows::Storage::Streams::DataWriter;
using winrt::Windows::Storage::Streams::InMemoryRandomAccessStream;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

const EncodableValue* FindValue(const EncodableMap& map,
                                const std::string& key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::string ReadString(const EncodableMap& map, const std::string& key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return {};
  }
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

bool ReadBool(const EncodableMap& map, const std::string& key,
              bool fallback = false) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  const auto* result = std::get_if<bool>(value);
  return result == nullptr ? fallback : *result;
}

int64_t ReadInt64(const EncodableMap& map, const std::string& key,
                  int64_t fallback = 0) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* large = std::get_if<int64_t>(value)) {
    return *large;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* floating = std::get_if<double>(value)) {
    return static_cast<int64_t>(*floating);
  }
  return fallback;
}

std::vector<uint8_t> ReadBytes(const EncodableMap& map,
                               const std::string& key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return {};
  }
  const auto* bytes = std::get_if<std::vector<uint8_t>>(value);
  return bytes == nullptr ? std::vector<uint8_t>() : *bytes;
}

TimeSpan MillisecondsToTimeSpan(int64_t milliseconds) {
  return TimeSpan{std::max<int64_t>(0, milliseconds) * 10000};
}

int64_t TimeSpanToMilliseconds(TimeSpan value) {
  return value.count() / 10000;
}

std::string ToUtf8(const winrt::hstring& value) {
  return winrt::to_string(value);
}

struct PendingCommand {
  std::string name;
  std::optional<int64_t> position_ms;
};

}  // namespace

struct BookMediaBridge::Impl {
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window),
        channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
            messenger, "book_and_quill/windows_media",
            &flutter::StandardMethodCodec::GetInstance())) {
    StartWorker();
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~Impl() { StopWorker(); }

  void StartWorker() {
    worker_thread_ = std::thread([this]() { WorkerMain(); });
    std::unique_lock<std::mutex> lock(worker_mutex_);
    worker_ready_condition_.wait(
        lock, [this]() { return worker_started_; });
  }

  void StopWorker() {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      stopping_ = true;
      worker_tasks_.clear();
    }
    worker_condition_.notify_one();
    if (worker_thread_.joinable()) {
      worker_thread_.join();
    }
  }

  void WorkerMain() {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
      {
        std::lock_guard<std::mutex> lock(worker_mutex_);
        worker_started_ = true;
        worker_available_ = false;
      }
      worker_ready_condition_.notify_all();
      return;
    }

    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      worker_started_ = true;
      worker_available_ = true;
    }
    worker_ready_condition_.notify_all();

    while (true) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(worker_mutex_);
        worker_condition_.wait(lock, [this]() {
          return stopping_ || !worker_tasks_.empty();
        });
        if (stopping_) {
          break;
        }
        task = std::move(worker_tasks_.front());
        worker_tasks_.pop_front();
      }
      try {
        task();
      } catch (...) {
        // A Windows media failure must not stop later media updates.
      }
    }

    CleanupMediaOnWorker();
    winrt::uninit_apartment();
  }

  bool PostWorkerTask(std::function<void()> task) {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      if (stopping_ || !worker_available_) {
        return false;
      }
      worker_tasks_.push_back(std::move(task));
    }
    worker_condition_.notify_one();
    return true;
  }

  void CleanupMediaOnWorker() {
    if (system_controls_) {
      try {
        system_controls_.ButtonPressed(button_token_);
        system_controls_.PlaybackPositionChangeRequested(position_token_);
        system_controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
        system_controls_.IsEnabled(false);
      } catch (...) {
      }
    }
    system_controls_ = nullptr;
    session_manager_ = nullptr;
  }

  bool EnsureSystemControls() {
    if (system_controls_) {
      return true;
    }
    try {
      auto interop = winrt::get_activation_factory<
          SystemMediaTransportControls, ::ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(
          window_,
          winrt::guid_of<
              winrt::Windows::Media::ISystemMediaTransportControls>(),
          winrt::put_abi(system_controls_)));

      system_controls_.IsEnabled(false);
      system_controls_.IsPlayEnabled(true);
      system_controls_.IsPauseEnabled(true);
      system_controls_.IsNextEnabled(true);
      system_controls_.IsPreviousEnabled(true);
      system_controls_.IsStopEnabled(false);
      button_token_ = system_controls_.ButtonPressed(
          [this](const SystemMediaTransportControls&,
                 const auto& arguments) {
            const auto button = arguments.Button();
            switch (button) {
              case SystemMediaTransportControlsButton::Play:
                QueueCommand("play");
                break;
              case SystemMediaTransportControlsButton::Pause:
                QueueCommand("pause");
                break;
              case SystemMediaTransportControlsButton::Next:
                QueueCommand("next");
                break;
              case SystemMediaTransportControlsButton::Previous:
                QueueCommand("previous");
                break;
              default:
                break;
            }
          });
      position_token_ = system_controls_.PlaybackPositionChangeRequested(
          [this](const SystemMediaTransportControls&,
                 const auto& arguments) {
            QueueCommand(
                "seek",
                TimeSpanToMilliseconds(arguments.RequestedPlaybackPosition()));
          });
      return true;
    } catch (...) {
      system_controls_ = nullptr;
      return false;
    }
  }

  bool EnsureSessionManager() {
    if (session_manager_) {
      return true;
    }
    try {
      session_manager_ =
          GlobalSystemMediaTransportControlsSessionManager::RequestAsync()
              .get();
      return static_cast<bool>(session_manager_);
    } catch (...) {
      session_manager_ = nullptr;
      return false;
    }
  }

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    try {
      if (call.method_name() == "initialize") {
        const bool available = PostWorkerTask([this]() {
          EnsureSystemControls();
          EnsureSessionManager();
        });
        result->Success(EncodableValue(available));
        return;
      }
      if (call.method_name() == "publishLocal") {
        const auto* arguments = call.arguments();
        const auto* map = arguments == nullptr
                              ? nullptr
                              : std::get_if<EncodableMap>(arguments);
        if (map == nullptr) {
          result->Error("bad_arguments",
                        "Local media update arguments are missing.");
        } else if (!PostWorkerTask(
                       [this, values = *map]() { PublishLocal(values); })) {
          result->Error("publish_failed",
                        "Windows rejected the local media update.");
        } else {
          result->Success();
        }
        return;
      }
      if (call.method_name() == "clearLocal") {
        if (PostWorkerTask([this]() { ClearLocal(); })) {
          result->Success();
        } else {
          result->Error("clear_failed",
                        "Windows media integration is unavailable.");
        }
        return;
      }
      if (call.method_name() == "poll") {
        result->Success(BuildPollResult());
        return;
      }
      if (call.method_name() == "controlExternal") {
        const auto* arguments = call.arguments();
        const auto* map = arguments == nullptr
                              ? nullptr
                              : std::get_if<EncodableMap>(arguments);
        if (map == nullptr) {
          result->Error("bad_arguments", "Media control arguments are missing.");
        } else if (!PostWorkerTask(
                       [this, values = *map]() { ControlExternal(values); })) {
          result->Error("control_failed",
                        "Windows media integration is unavailable.");
        } else {
          result->Success();
        }
        return;
      }
      result->NotImplemented();
    } catch (const winrt::hresult_error& error) {
      result->Error("windows_media_error", ToUtf8(error.message()));
    } catch (const std::exception& error) {
      result->Error("windows_media_error", error.what());
    } catch (...) {
      result->Error("windows_media_error",
                    "Unknown Windows media-session error.");
    }
  }

  bool PublishLocal(const EncodableMap& arguments) {
    if (!EnsureSystemControls()) {
      return false;
    }
    const std::string track_id = ReadString(arguments, "trackId");
    const std::string title = ReadString(arguments, "title");
    const std::string artist = ReadString(arguments, "artist");
    const std::string album = ReadString(arguments, "album");
    const int64_t position_ms = ReadInt64(arguments, "positionMs");
    const int64_t duration_ms =
        std::max<int64_t>(0, ReadInt64(arguments, "durationMs"));
    const bool paused = ReadBool(arguments, "isPaused", false);

    system_controls_.IsEnabled(true);
    system_controls_.IsPlayEnabled(true);
    system_controls_.IsPauseEnabled(true);
    system_controls_.IsNextEnabled(true);
    system_controls_.IsPreviousEnabled(true);

    auto updater = system_controls_.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
    auto properties = updater.MusicProperties();
    properties.Title(winrt::to_hstring(title));
    properties.Artist(winrt::to_hstring(artist));
    properties.AlbumArtist(winrt::to_hstring(artist));
    properties.AlbumTitle(winrt::to_hstring(album));

    if (track_id != published_track_id_) {
      const auto artwork = ReadBytes(arguments, "artwork");
      if (!artwork.empty()) {
        InMemoryRandomAccessStream stream;
        DataWriter writer(stream.GetOutputStreamAt(0));
        writer.WriteBytes(artwork);
        writer.StoreAsync().get();
        writer.FlushAsync().get();
        writer.DetachStream();
        stream.Seek(0);
        updater.Thumbnail(RandomAccessStreamReference::CreateFromStream(stream));
      }
      published_track_id_ = track_id;
    }
    updater.Update();

    SystemMediaTransportControlsTimelineProperties timeline;
    const auto start = MillisecondsToTimeSpan(0);
    const auto end = MillisecondsToTimeSpan(duration_ms);
    const auto position = MillisecondsToTimeSpan(
        std::clamp<int64_t>(position_ms, 0, duration_ms));
    timeline.StartTime(start);
    timeline.MinSeekTime(start);
    timeline.Position(position);
    timeline.MaxSeekTime(end);
    timeline.EndTime(end);
    system_controls_.UpdateTimelineProperties(timeline);
    system_controls_.PlaybackStatus(paused ? MediaPlaybackStatus::Paused
                                           : MediaPlaybackStatus::Playing);
    return true;
  }

  void ClearLocal() {
    published_track_id_.clear();
    if (!system_controls_) {
      return;
    }
    try {
      system_controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
      auto updater = system_controls_.DisplayUpdater();
      updater.ClearAll();
      updater.Update();
      system_controls_.IsEnabled(false);
    } catch (...) {
    }
  }

  EncodableValue BuildPollResult() {
    RequestExternalRefresh();
    EncodableMap response;
    response[EncodableValue("commands")] =
        EncodableValue(DrainCommands());
    std::optional<EncodableMap> external;
    {
      std::lock_guard<std::mutex> lock(external_mutex_);
      external = external_cache_;
    }
    if (external.has_value()) {
      response[EncodableValue("external")] =
          EncodableValue(std::move(*external));
    } else {
      response[EncodableValue("external")] = EncodableValue();
    }
    return EncodableValue(std::move(response));
  }

  void RequestExternalRefresh() {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      if (stopping_ || !worker_available_ || external_refresh_pending_) {
        return;
      }
      external_refresh_pending_ = true;
      worker_tasks_.push_back([this]() {
        std::optional<EncodableMap> external;
        try {
          external = ReadExternalSession();
        } catch (...) {
          external = std::nullopt;
        }
        {
          std::lock_guard<std::mutex> lock(external_mutex_);
          external_cache_ = std::move(external);
        }
        {
          std::lock_guard<std::mutex> lock(worker_mutex_);
          external_refresh_pending_ = false;
        }
      });
    }
    worker_condition_.notify_one();
  }

  std::optional<EncodableMap> ReadExternalSession() {
    if (!EnsureSessionManager()) {
      return std::nullopt;
    }
    const GlobalSystemMediaTransportControlsSession session =
        session_manager_.GetCurrentSession();
    if (!session) {
      external_artwork_key_.clear();
      return std::nullopt;
    }

    const auto media = session.TryGetMediaPropertiesAsync().get();
    const auto playback = session.GetPlaybackInfo();
    const auto timeline = session.GetTimelineProperties();
    const auto controls = playback.Controls();
    const std::string source_id = ToUtf8(session.SourceAppUserModelId());
    const std::string title = ToUtf8(media.Title());
    const std::string artist = ToUtf8(media.Artist());
    const std::string album = ToUtf8(media.AlbumTitle());
    const std::string artwork_key =
        source_id + "\n" + title + "\n" + artist + "\n" + album;

    const int64_t start_ms = TimeSpanToMilliseconds(timeline.StartTime());
    const int64_t end_ms = TimeSpanToMilliseconds(timeline.EndTime());
    const int64_t position_ms = TimeSpanToMilliseconds(timeline.Position());
    const int64_t duration_ms = std::max<int64_t>(0, end_ms - start_ms);
    const int64_t relative_position =
        std::clamp<int64_t>(position_ms - start_ms, 0, duration_ms);
    const auto status = playback.PlaybackStatus();
    const bool paused =
        status != GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                      Playing;

    EncodableMap value;
    value[EncodableValue("available")] = EncodableValue(true);
    value[EncodableValue("sourceId")] = EncodableValue(source_id);
    value[EncodableValue("title")] = EncodableValue(title);
    value[EncodableValue("artist")] = EncodableValue(artist);
    value[EncodableValue("album")] = EncodableValue(album);
    value[EncodableValue("positionMs")] = EncodableValue(relative_position);
    value[EncodableValue("durationMs")] = EncodableValue(duration_ms);
    value[EncodableValue("isPaused")] = EncodableValue(paused);
    value[EncodableValue("canPlay")] =
        EncodableValue(controls.IsPlayEnabled());
    value[EncodableValue("canPause")] =
        EncodableValue(controls.IsPauseEnabled());
    value[EncodableValue("canPrevious")] =
        EncodableValue(controls.IsPreviousEnabled());
    value[EncodableValue("canNext")] =
        EncodableValue(controls.IsNextEnabled());
    value[EncodableValue("canSeek")] =
        EncodableValue(controls.IsPlaybackPositionEnabled());

    if (artwork_key != external_artwork_key_) {
      const auto thumbnail = media.Thumbnail();
      if (thumbnail) {
        try {
          const auto stream = thumbnail.OpenReadAsync().get();
          const uint64_t stream_size = stream.Size();
          const uint32_t size = static_cast<uint32_t>(
              std::min<uint64_t>(stream_size, 8 * 1024 * 1024));
          if (size > 0) {
            DataReader reader(stream.GetInputStreamAt(0));
            reader.LoadAsync(size).get();
            std::vector<uint8_t> artwork(size);
            reader.ReadBytes(artwork);
            value[EncodableValue("artwork")] =
                EncodableValue(std::move(artwork));
            external_artwork_key_ = artwork_key;
          }
        } catch (...) {
        }
      }
    }
    return value;
  }

  void ControlExternal(const EncodableMap& arguments) {
    if (!EnsureSessionManager()) {
      return;
    }
    const auto session = session_manager_.GetCurrentSession();
    if (!session) {
      return;
    }
    const std::string command = ReadString(arguments, "command");
    if (command == "play") {
      session.TryPlayAsync().get();
    } else if (command == "pause") {
      session.TryPauseAsync().get();
    } else if (command == "next") {
      session.TrySkipNextAsync().get();
    } else if (command == "previous") {
      session.TrySkipPreviousAsync().get();
    } else if (command == "seek") {
      const int64_t position_ms = ReadInt64(arguments, "positionMs");
      session.TryChangePlaybackPositionAsync(
                 std::max<int64_t>(0, position_ms) * 10000)
          .get();
    }
  }

  void QueueCommand(const std::string& name,
                    std::optional<int64_t> position_ms = std::nullopt) {
    std::lock_guard<std::mutex> lock(command_mutex_);
    pending_commands_.push_back(PendingCommand{name, position_ms});
  }

  EncodableList DrainCommands() {
    std::vector<PendingCommand> commands;
    {
      std::lock_guard<std::mutex> lock(command_mutex_);
      commands.swap(pending_commands_);
    }
    EncodableList result;
    result.reserve(commands.size());
    for (const auto& command : commands) {
      EncodableMap value;
      value[EncodableValue("name")] = EncodableValue(command.name);
      if (command.position_ms.has_value()) {
        value[EncodableValue("positionMs")] =
            EncodableValue(*command.position_ms);
      }
      result.emplace_back(std::move(value));
    }
    return result;
  }

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::thread worker_thread_;
  std::mutex worker_mutex_;
  std::condition_variable worker_condition_;
  std::condition_variable worker_ready_condition_;
  std::deque<std::function<void()>> worker_tasks_;
  bool worker_started_ = false;
  bool worker_available_ = false;
  bool stopping_ = false;
  bool external_refresh_pending_ = false;
  SystemMediaTransportControls system_controls_{nullptr};
  GlobalSystemMediaTransportControlsSessionManager session_manager_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token position_token_{};
  std::string published_track_id_;
  std::string external_artwork_key_;
  std::mutex external_mutex_;
  std::optional<EncodableMap> external_cache_;
  std::mutex command_mutex_;
  std::vector<PendingCommand> pending_commands_;
};

BookMediaBridge::BookMediaBridge(flutter::BinaryMessenger* messenger,
                                 HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

BookMediaBridge::~BookMediaBridge() = default;
