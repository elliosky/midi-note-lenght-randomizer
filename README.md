ITA:

"Umanizza Fine Note MIDI" è uno script LUA per REAPER che permette di aggiungere variazioni casuali alla durata delle note MIDI mantenendo invariato il loro punto di inizio. 
Questo strumento è particolarmente utile per rendere più naturali e meno meccaniche le performance MIDI programmate, simulando le variazioni temporali che si verificano naturalmente durante l'esecuzione musicale dal vivo.
L'intensità della randomizzazione è regolabile tramite un cursore che va da 0% a 100%. Un valore basso produrrà variazioni sottili e naturali, mentre valori più alti genereranno modifiche più pronunciate.


L'interfaccia grafica è intuitiva e reattiva, oltre che scalabile alle dimensioni della finestra. 
Presenta due radio button per scegliere tra l'applicazione a tutte le note o solo a quelle selezionate, un cursore per regolare l'intensità dell'effetto con indicatore percentuale e due pulsanti principali per generare un nuovo seed casuale e per eseguire il processo.


Per quanto riguarda le prestazioni, lo script è ottimizzato per gestire progetti con decine di migliaia di note MIDI senza problemi significativi. 
Utilizza tecniche di caching per le funzioni più utilizzate e algoritmi efficienti per il processamento degli eventi MIDI. 
La finestra delle statistiche mostra informazioni dettagliate sul tempo di elaborazione, il numero di note processate e la velocità di processamento, permettendo di monitorare le performance in tempo reale.


Il controllo dello script può avvenire sia tramite mouse che tramite scorciatoie da tastiera. 
Il tasto Invio in particolare esegue il processo e chiude automaticamente la finestra, rendendo l'utilizzo estremamente rapido se l'avvio è associato a una hotkey di Reaper. 
Il tasto Esc chiude lo script, mentre 'r' o 'R' generano un nuovo seed casuale. 
Per utilizzare le scorciatoie è necessario che la finestra dello script sia attiva e che sia aperto un editor MIDI.


Lo script salva automaticamente tutte le impostazioni tra le sessioni, inclusi il valore di intensità e la modalità di applicazione. 
Questo permette di riprendere il lavoro con le stesse configurazioni utilizzate in precedenza.


Dal punto di vista tecnico lo script utilizza un approccio a due passate per il processamento degli eventi MIDI. 
Nella prima passata (ispirata a un modello di parsing manuale di @juliansader) identifica tutte le coppie di Note On e Note Off, mentre nella seconda ricostruisce la sequenza MIDI con le modifiche applicate. 
L'algoritmo di randomizzazione è progettato per essere musicalmente sensato, specialmente a basse intensità. Calcola le variazioni sia in termini di PPQ (Pulses Per Quarter note) che in tempo reale, applicando poi la variazione che risulta più appropriata nel contesto specifico. 
Questo doppio approccio assicura risultati coerenti indipendentemente dalle automazioni di tempo del progetto o dalla risoluzione MIDI utilizzata.
Lo script è stato limitatamente testato su versioni di Reaper successive alla 7 su sistemi Windows. 


Non richiede librerie esterne o plugin aggiuntivi, utilizzando esclusivamente le API native di REAPER.
Per utilizzare lo script è sufficiente copiarlo nella cartella degli script di REAPER e assegnargli eventualmente una scorciatoia da tastiera per un accesso rapido. 
Una volta lanciato, lo script rileva automaticamente il take MIDI attivo nell'editor e permette di iniziare immediatamente il processo di umanizzazione senza necessità di configurazioni aggiuntive.


ENG:

"Midi note lenght randomizer" is a LUA script for REAPER that allows you to add random variations to the duration of MIDI notes while maintaining their starting point.
This tool is particularly useful for making programmed MIDI performances more natural and less mechanical, simulating the timing variations that naturally occur during live music performance.
The intensity of the randomization can be adjusted using a slider ranging from 0% to 100%. A low value will produce subtle and natural variations, while higher values will generate more pronounced changes.


The graphical interface is intuitive and responsive, as well as scalable to the size of the window.
It features two radio buttons to choose between applying it to all notes or just selected ones, a slider to adjust the effect intensity with a percentage indicator, and two main buttons to generate a new random seed and to execute the process.


Regarding performance, the script is optimized to handle projects with tens of thousands of MIDI notes without significant issues.
It uses caching techniques for the most commonly used functions and efficient algorithms for processing MIDI events.
The statistics window displays detailed information on processing time, the number of notes processed, and the processing speed, allowing you to monitor performance in real time.


The script can be controlled using both the mouse and keyboard shortcuts.
The Enter key executes the process and automatically closes the window, making it extremely quick to use if launched from a Reaper hotkey.
The Esc key closes the script, while 'r' or 'R' generates a new random seed.
To use the shortcuts, the script window must be active and a MIDI editor must be open.


The script automatically saves all settings between sessions, including the intensity value and application mode.
This allows you to resume work with the same configurations used previously.


Technically, the script uses a two-pass approach to processing MIDI events.
In the first pass (inspired by a manual parsing model by @juliansader), it identifies all note-on and note-off pairs, while in the second pass, it reconstructs the MIDI sequence with the applied changes.
The randomization algorithm is designed to be musically sensible, especially at low intensities. It calculates the changes both in terms of PPQ (Pulses Per Quarter Note) and in real time, then applying the most appropriate change in the specific context.
This dual approach ensures consistent results regardless of the project's tempo automations or the MIDI resolution used.
The script has been limitedly tested on Reaper versions later than 7 on Windows systems.


It does not require external libraries or additional plugins, using only REAPER's native APIs.
To use the script, simply copy it into the REAPER scripts folder and assign a keyboard shortcut for quick access.
Once launched, the script automatically detects the active MIDI take in the editor and allows you to immediately begin the humanization process without the need for additional configuration.
