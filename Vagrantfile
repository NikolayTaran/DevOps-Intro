# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Lab 5 — QuickNotes VM (Vagrant + VirtualBox)
# 2 vCPU / 1024 MB, Go 1.24.5, host 18080 -> guest 8080 (loopback only)

Vagrant.configure("2") do |config|
  # Публичный бокс Ubuntu 24.04 LTS из официального каталога HashiCorp
  config.vm.box = "bento/ubuntu-24.04"

  # Первый boot в режиме совместимости с Hyper-V медленный — даём больше времени
  config.vm.boot_timeout = 900

  # Hostname, идентифицирующий проект
  config.vm.hostname = "quicknotes-lab5"

  # Проброс порта: NAT, host 127.0.0.1:18080 -> guest:8080
  config.vm.network "forwarded_port",
    guest: 8080, host: 18080, host_ip: "127.0.0.1"

  # Синхронизация кода: односторонний rsync host -> guest
  config.vm.synced_folder "app", "/home/vagrant/quicknotes",
    type: "rsync",
    rsync__exclude: [".git/", "bin/", "tmp/"]

  # Жёсткий лимит ресурсов — никакого овер-провижининга
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "quicknotes-lab5"
    vb.cpus   = 2
    vb.memory = 1024
  end

  # Провижининг: установка закреплённого Go 1.24.5
  config.vm.provision "shell", path: "scripts/install-go.sh"

  # Подсказка после vagrant up
  config.vm.post_up_message = <<~MSG
    QuickNotes VM is up!
      Go:          vagrant ssh -c 'go version'
      Health:      curl http://127.0.0.1:18080/health
  MSG
end