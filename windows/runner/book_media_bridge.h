#pragma once

#include <flutter/binary_messenger.h>

#include <memory>
#include <windows.h>

class BookMediaBridge {
 public:
  BookMediaBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~BookMediaBridge();

  BookMediaBridge(const BookMediaBridge&) = delete;
  BookMediaBridge& operator=(const BookMediaBridge&) = delete;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
