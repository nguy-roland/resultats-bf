require 'yaml'
require 'fileutils'
require 'securerandom'

GROUPE        = 3
NB_APP        = (ENV['NB_APP'] || 2).to_i
RESEAU        = "192.168.#{55 + GROUPE}"
BOITE         = "bento/ubuntu-24.04"
VERSION_BOITE = "202510.26.0"
RACINE        = File.dirname(__FILE__)

# Au-delà de 9, app10 prendrait .30 et app11 l'adresse de bdd1 (.31).
unless (2..9).include?(NB_APP)
  abort "NB_APP doit être compris entre 2 et 9 (reçu : #{NB_APP})."
end

# Source unique de vérité : les VM et la configuration du répartiteur
# sont engendrées à partir de cette table.
NOEUDS = []
NOEUDS << { "nom" => "bdd1", "ip" => "#{RESEAU}.31", "memoire" => 768, "role" => "bdd" }
NOEUDS << { "nom" => "bdd2", "ip" => "#{RESEAU}.32", "memoire" => 768, "role" => "replique" }
(1..NB_APP).each do |numero|
NOEUDS << { "nom" => "app#{numero}", "ip" => "#{RESEAU}.#{20 + numero}", "memoire" => 512, "role" => "app", "port" => 8000 }
end
NOEUDS << { "nom" => "lb1", "ip" => "#{RESEAU}.11", "memoire" => 512, "role" => "lb" }

# Les scripts de provisionnement liront ce fichier dans /vagrant/config/noeuds.yml
FileUtils.mkdir_p(File.join(RACINE, "config"))
File.write(File.join(RACINE, "config", "noeuds.yml"), NOEUDS.to_yaml)

# Secrets : au premier lancement, le .env est créé depuis .env.exemple
# avec un mot de passe aléatoire à la place de chaque "a_remplacer".
FICHIER_ENV = File.join(RACINE, ".env")
unless File.exist?(FICHIER_ENV)
  modele = File.read(File.join(RACINE, ".env.exemple"), encoding: "UTF-8")
  File.write(FICHIER_ENV, modele.gsub("a_remplacer") { SecureRandom.alphanumeric(20) })
  File.chmod(0600, FICHIER_ENV)
end

# Variables du .env, transmises plus tard aux scripts de provisionnement.
SECRETS = File.readlines(FICHIER_ENV, chomp: true, encoding: "UTF-8")
  .reject { |ligne| ligne.strip.empty? || ligne.start_with?("#") }
  .map { |ligne| ligne.split("=", 2) }
  .to_h

Vagrant.configure("2") do |config|
  config.vm.box              = BOITE
  config.vm.box_version      = VERSION_BOITE
  config.vm.box_check_update = false

  NOEUDS.each do |noeud|
    config.vm.define noeud["nom"] do |machine|
      machine.vm.hostname = noeud["nom"]
      machine.vm.network "private_network", ip: noeud["ip"]
      if noeud["role"] == "lb"
        machine.vm.network "forwarded_port", guest: 80, host: 8080
      end
      machine.vm.provider "virtualbox" do |virtualbox|
        virtualbox.name   = "resultats-bf-#{noeud['nom']}"
        virtualbox.memory = noeud["memoire"]
        virtualbox.cpus   = 1
      end

      # Socle commun à toutes les machines, puis script propre au rôle.
      machine.vm.provision "shell", path: "scripts/commun.sh", env: SECRETS
      machine.vm.provision "shell", path: "scripts/#{noeud['role']}.sh", env: SECRETS
    end
  end
end