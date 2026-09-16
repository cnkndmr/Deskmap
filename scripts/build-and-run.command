#!/bin/bash
# Finder'dan çift tıklanınca: çalışan Deskmap'i kapat, derle, yeniden aç.
# Çıktı build/last-build.log dosyasına da yazılır.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
{
  echo "=== $(date) ==="
  pkill -x Deskmap && sleep 1
  make run
  echo "=== exit: $? ==="
} 2>&1 | tee build/last-build.log
