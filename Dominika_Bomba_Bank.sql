/*tworzenie tabel */

CREATE DATABASE bank_nowy;


USE bank_nowy;

	/*KLIENCI*/
	CREATE TABLE Klienci(
		id_klienta INT PRIMARY key AUTO_INCREMENT ,
		imie VARCHAR(50) NOT NULL,
		nazwisko VARCHAR(50) NOT NULL,
		pesel CHAR(11) UNIQUE,
		adres VARCHAR(255),
		telefon VARCHAR(15)
	);
	/*PROFIL*/
	CREATE TABLE profil(
		id_klienta INT, 
		login VARCHAR(50) UNIQUE ,
		haslo_hash VARCHAR(255)
	);
	
	ALTER TABLE profil
	RENAME TO profil_internetowy;
	
	ALTER TABLE profil_internetowy
	ADD CONSTRAINT fk_id_klienta_profil_internetowy
	FOREIGN KEY (id_klienta) REFERENCES Klienci(id_klienta);

	/*KONTA*/
	CREATE TABLE konta(
		id_klienta INT,
		id_konta INT primary key AUTO_INCREMENT,
		numer_konta VARCHAR(26) UNIQUE, 
		saldo DECIMAL(15,2) DEFAULT '0.00',
		FOREIGN KEY (id_klienta) REFERENCES klienci(id_klienta)
	  ON UPDATE CASCADE
    ON DELETE RESTRICT
	);

	ALTER TABLE konta
	ADD CONSTRAINT fk_id_klienta_konta
	FOREIGN KEY (id_klienta) REFERENCES klienci(id_klienta);

/*PRZELEWY*/
	CREATE TABLE Przelewy(
	    id_konta_nadawcy INT,
	    id_konta_odbiorcy INT,
	    kwota DECIMAL(15,2), 
	    data_przelewu DATETIME DEFAULT CURRENT_TIMESTAMP, 
	    PRIMARY KEY (id_konta_nadawcy, id_konta_odbiorcy, data_przelewu),
	    FOREIGN KEY (id_konta_nadawcy) REFERENCES Konta(id_konta),
	    FOREIGN KEY (id_konta_odbiorcy) REFERENCES Konta(id_konta)
	);



	/*KARTY*/
	CREATE TABLE karty(
		id_konta INT, 
		id_karty INT PRIMARY KEY AUTO_INCREMENT

	);
	DROP TABLE karty;

	CREATE TABLE karty(
	id_konta INT, 
	id_karty INT PRIMARY KEY AUTO_INCREMENT, 
	numer_karty VARCHAR(16) UNIQUE, 
	data_waznosci DATE,
	cvv CHAR(3),
	FOREIGN KEY (id_konta) REFERENCES konta(id_konta)
	);
	
	CREATE TABLE banki (
    id_banku INT PRIMARY KEY AUTO_INCREMENT, 
    nazwa_banku VARCHAR(100) NOT NULL, 
    czas_otwarcia TIMESTAMP, 
    czas_zamkniecia TIMESTAMP,
    otwarte_codziennie BOOL DEFAULT TRUE
	); 
	
	/*PRACOWNICY*/
	CREATE TABLE pracownicy(
		id_pracownika INT PRIMARY KEY AUTO_INCREMENT,
		id_banku INT, 
		imie VARCHAR(50),
		nazwisko VARCHAR(50),
		stanowisko VARCHAR(50),
		telefon VARCHAR(15),
		poczatek_stazu DATE,
		pensja FLOAT,
        FOREIGN KEY (id_banku) REFERENCES banki(id_banku)
    );
    
	/*klienci_karty (łącznikowa)*/
	CREATE TABLE klienci_pracownicy(
	id_pracownika INT, 
	id_klienta INT,
	FOREIGN KEY (id_klienta) REFERENCES Klienci(id_klienta) ON DELETE CASCADE, 
	FOREIGN KEY (id_pracownika) REFERENCES Pracownicy(id_pracownika) ON DELETE CASCADE 
	);
	
	/*klienci_transakcje */
	CREATE TABLE transakcje(
	id_konta INT, 
	id_transakcji INT primary key AUTO_INCREMENT, 
	kwota DECIMAL(15,2) DEFAULT null,
	data_transakcji DATETIME DEFAULT CURRENT_TIMESTAMP,
	typ ENUM('wpłata', 'wypłata'),
	FOREIGN KEY (id_konta) REFERENCES Konta(id_konta),	
	CHECK (kwota > 0)
	);	
	
	CREATE SEQUENCE transakcje_seq
	START WITH 1
	INCREMENT BY 1
	NOCACHE
	NOCYCLE;
	
	
	

	/*LOKALIZACJE*/
	CREATE TABLE lokalizacje (
	    id_lokalizacji INT PRIMARY KEY AUTO_INCREMENT,
	    adres VARCHAR(255) NOT NULL,
	    miasto VARCHAR(50),
	    kod_pocztowy CHAR(6)
	);
	
	ALTER TABLE lokalizacje
	ADD COLUMN latitude DECIMAL(9, 6),
	ADD COLUMN longitude DECIMAL(9, 6);


	/*łącznikowa (banki - lokalizacje)*/
	CREATE TABLE banki_lokalizacje (
	    id_banku INT,
	    id_lokalizacji INT,
	    PRIMARY KEY (id_banku, id_lokalizacji),
	    FOREIGN KEY (id_banku) REFERENCES banki(id_banku) ON DELETE CASCADE,
	    FOREIGN KEY (id_lokalizacji) REFERENCES lokalizacje(id_lokalizacji) ON DELETE CASCADE
	);

	
	


/*trigery*/

	/*by przy probie przelewu saldo nie bylo mniejsze od 0*/
	DELIMITER //
	CREATE TRIGGER zapobiegaj_negatywnemu_saldzie
	BEFORE INSERT ON Przelewy
	FOR EACH ROW
	BEGIN
	    DECLARE saldo DECIMAL(15,2);
	    SELECT saldo INTO saldo FROM konta WHERE id_konta = NEW.id_konta_nadawcy;
	    IF saldo - NEW.kwota < 0 THEN
	        SIGNAL SQLSTATE '45000'
	        SET MESSAGE_TEXT = 'Nie można wykonać przelewu - niewystarczające środki!';
	    ELSE
	        UPDATE konta SET saldo = saldo - NEW.kwota WHERE id_konta = NEW.id_konta_nadawcy;
	        UPDATE konta SET saldo = saldo + NEW.kwota WHERE id_konta = NEW.id_konta_odbiorcy;
	    END IF;
	END //
	DELIMITER ;
	
	
	/*zmienianie salda na koncie - przy wykonywaniu transakcji*/
	DELIMITER //
	CREATE TRIGGER aktualizuj_saldo_po_przelewie
	AFTER INSERT ON Przelewy
	FOR EACH ROW
	BEGIN
	    UPDATE konta 
	    SET saldo = saldo - NEW.kwota 
	    WHERE id_konta = NEW.id_konta_nadawcy;
	 UPDATE konta 
	    SET saldo = saldo + NEW.kwota 
	    WHERE id_konta = NEW.id_konta_odbiorcy;
	END //
	DELIMITER ;
	
	/*funkcja do trigera*/
	
		DELIMITER //
		CREATE FUNCTION czy_mozna_wyplacic(id_konta_param INT, kwota_param DECIMAL(15,2))
		RETURNS BOOLEAN
		DETERMINISTIC
		BEGIN
		    DECLARE obecne_saldo DECIMAL(15,2);
			  SELECT saldo INTO obecne_saldo FROM konta WHERE id_konta = id_konta_param;
		    IF obecne_saldo >= kwota_param THEN
		        RETURN TRUE;  -- Można wypłacić
		    ELSE
		        RETURN FALSE; -- Nie można wypłacić
		    END IF;
		END //
		DELIMITER ;

	
	/*by przy próbie wypłaty pieniędzy większych niż saldo, nie można było*/
		DELIMITER //
		CREATE TRIGGER zabezpiecz_przed_negatywnym_saldem
		BEFORE INSERT ON transakcje
		FOR EACH ROW
		BEGIN
		    IF NEW.typ = 'wypłata' THEN
		        IF NOT czy_mozna_wyplacic(NEW.id_konta, NEW.kwota) THEN
		             SET NEW.id_transakcji = NULL;
		        ELSE
		            UPDATE konta SET saldo = saldo - NEW.kwota WHERE id_konta = NEW.id_konta;
		        END IF;
		    ELSE
		        UPDATE konta SET saldo = saldo + NEW.kwota WHERE id_konta = NEW.id_konta;
		    END IF;
		END //
		DELIMITER ;
	/*idnexy b-tree*/
	
		
	CREATE INDEX idx_klienci_pesel ON Klienci(pesel);	
		
	CREATE INDEX idx_konta_numer ON konta(numer_konta);
	
	CREATE INDEX idx_przelewy_nadawca ON Przelewy(id_konta_nadawcy);
	
	CREATE INDEX idx_przelewy_odbiorca ON Przelewy(id_konta_odbiorcy);

INSERT INTO Klienci (imie, nazwisko, pesel, adres, telefon) VALUES
('Tomasz', 'Lewandowski', '0619702741', 'Katowice', '+48994595984'),
('Krzysztof', 'Szymański', '8293818865', 'Wrocław', '+48763861257'),
('Marcin', 'Jankowski', '6242039197', 'Kraków', '+48322435776'),
('Agnieszka', 'Wójcik', '7288639280', 'Gdańsk', '+48957980698'),
('Anna', 'Lewandowski', '1734309782', 'Łódź', '+48346061121'),
('Katarzyna', 'Kaczmarek', '9185104696', 'Wrocław', '+48788868120'),
('Joanna', 'Mazur', '7097262690', 'Poznań', '+48431669267'),
('Katarzyna', 'Kamiński', '4785999024', 'Kraków', '+48485756196'),
('Jan', 'Nowak', '2846584113', 'Warszawa', '+48741403228'),
('Magdalena', 'Wójcik', '0099512872', 'Gdańsk', '+48579406421'),
('Piotr', 'Jankowski', '8051307947', 'Poznań', '+48190509465'),
('Marcin', 'Kamiński', '5993510829', 'Łódź', '+48964921110'),
('Magdalena', 'Lewandowski', '5358269114', 'Poznań', '+48605360122'),
('Katarzyna', 'Szymański', '4174834062', 'Gdańsk', '+48127253751'),
('Andrzej', 'Wójcik', '8887678119', 'Gdańsk', '+48285041431'),
('Adam', 'Szymański', '2378365203', 'Wrocław', '+48656415593'),
('Zofia', 'Kaczmarek', '9080882336', 'Lublin', '+48214260002'),
('Katarzyna', 'Szymański', '6155386732', 'Lublin', '+48417359025'),
('Rafał', 'Wiśniewski', '1254385405', 'Poznań', '+48640464609'),
('Tomasz', 'Mazur', '5886488015', 'Szczecin', '+48600063657'),
('Rafał', 'Nowak', '2605579637', 'Łódź', '+48302715385'),
('Anna', 'Mazur', '2182624526', 'Wrocław', '+48522746180'),
('Jan', 'Jankowski', '5929677643', 'Poznań', '+48880074112'),
('Zofia', 'Mazur', '1192104232', 'Warszawa', '+48517619476'),
('Barbara', 'Wójcik', '0788175658', 'Kraków', '+48590074298'),
('Tomasz', 'Kamiński', '6597613751', 'Warszawa', '+48358380246'),
('Adam', 'Wójcik', '2779989785', 'Szczecin', '+48841093771'),
('Monika', 'Wójcik', '0304638458', 'Łódź', '+48837474337'),
('Ewa', 'Wiśniewski', '4333643714', 'Lublin', '+48806927183'),
('Agnieszka', 'Kamiński', '4286077250', 'Poznań', '+48277860839'),
('Monika', 'Kowalski', '1199267732', 'Szczecin', '+48683903301'),
('Krzysztof', 'Wiśniewski', '0407691753', 'Poznań', '+48414023639'),
('Krzysztof', 'Wiśniewski', '1015484207', 'Wrocław', '+48857706187'),
('Rafał', 'Nowak', '3227834635', 'Bydgoszcz', '+48489478375'),
('Marek', 'Jankowski', '1208421779', 'Łódź', '+48764457440'),
('Anna', 'Jankowski', '2442843054', 'Bydgoszcz', '+48591887969'),
('Rafał', 'Wiśniewski', '4540997329', 'Kraków', '+48305199524'),
('Barbara', 'Kamiński', '3372459370', 'Łódź', '+48405170409'),
('Joanna', 'Mazur', '6889138388', 'Szczecin', '+48607589320'),
('Anna', 'Jankowski', '6934047364', 'Poznań', '+48485685484'),
('Zofia', 'Mazur', '9852834678', 'Gdańsk', '+48162297973'),
('Agnieszka', 'Jankowski', '5032854422', 'Warszawa', '+48457196618'),
('Agnieszka', 'Nowak', '6622937424', 'Bydgoszcz', '+48251540576'),
('Maria', 'Mazur', '5101597588', 'Poznań', '+48625032998'),
('Magdalena', 'Wiśniewski', '0854011658', 'Warszawa', '+48115303598'),
('Paweł', 'Lewandowski', '7850191825', 'Poznań', '+48804407563'),
('Joanna', 'Szymański', '7142200540', 'Katowice', '+48239629538'),
('Agnieszka', 'Nowak', '2727081194', 'Katowice', '+48782095200'),
('Marek', 'Kamiński', '5494602063', 'Katowice', '+48444675120'),
('Zofia', 'Kamiński', '1052027356', 'Warszawa', '+48668018230'),
('Marcin', 'Kowalski', '2302904355', 'Szczecin', '+48516534451'),
('Joanna', 'Szymański', '9669396658', 'Szczecin', '+48604025950'),
('Barbara', 'Nowak', '2036416364', 'Gdańsk', '+48571392142'),
('Paweł', 'Lewandowski', '7500324709', 'Katowice', '+48339089641'),
('Maria', 'Wójcik', '6814956504', 'Lublin', '+48792321557'),
('Marek', 'Wiśniewski', '3260304415', 'Poznań', '+48568936920'),
('Andrzej', 'Lewandowski', '2102582897', 'Łódź', '+48752150347'),
('Monika', 'Wójcik', '3958369208', 'Szczecin', '+48436426034'),
('Tomasz', 'Szymański', '7368795113', 'Kraków', '+48398268486'),
('Paweł', 'Wiśniewski', '7946985367', 'Warszawa', '+48842847032'),
('Magdalena', 'Wiśniewski', '6535031052', 'Poznań', '+48543726444'),
('Zofia', 'Szymański', '1086190096', 'Gdańsk', '+48706261484'),
('Barbara', 'Kowalski', '3695538620', 'Gdańsk', '+48607029572'),
('Adam', 'Lewandowski', '1286144649', 'Szczecin', '+48134677014'),
('Rafał', 'Wójcik', '1058779813', 'Warszawa', '+48649438673'),
('Marcin', 'Wiśniewski', '9316474819', 'Lublin', '+48306302005'),
('Paweł', 'Nowak', '8197979683', 'Bydgoszcz', '+48580964015'),
('Piotr', 'Wiśniewski', '6435834575', 'Łódź', '+48144728243'),
('Magdalena', 'Jankowski', '5853941830', 'Gdańsk', '+48239763830'),
('Tomasz', 'Wójcik', '3881989499', 'Lublin', '+48595428082'),
('Agnieszka', 'Wiśniewski', '1025287746', 'Wrocław', '+48778676295'),
('Paweł', 'Kamiński', '9142392835', 'Wrocław', '+48969222046'),
('Marcin', 'Kamiński', '0785414661', 'Wrocław', '+48782899102'),
('Rafał', 'Kamiński', '0359851545', 'Łódź', '+48669049393'),
('Marcin', 'Lewandowski', '0139208667', 'Katowice', '+48774712178'),
('Rafał', 'Szymański', '8548865161', 'Gdańsk', '+48689668949'),
('Monika', 'Kowalski', '4171377804', 'Warszawa', '+48626023737'),
('Rafał', 'Kowalski', '4518451137', 'Bydgoszcz', '+48500271714'),
('Piotr', 'Lewandowski', '7612245125', 'Warszawa', '+48339109443'),
('Joanna', 'Nowak', '6072904730', 'Warszawa', '+48228148040'),
('Katarzyna', 'Wiśniewski', '8468190858', 'Poznań', '+48526848736'),
('Maria', 'Wiśniewski', '3319596928', 'Warszawa', '+48949794260'),
('Magdalena', 'Jankowski', '2627272650', 'Łódź', '+48872411733'),
('Marek', 'Wójcik', '7823333911', 'Gdańsk', '+48276893147'),
('Ewa', 'Jankowski', '0893530878', 'Lublin', '+48663286023'),
('Zofia', 'Mazur', '4556039966', 'Bydgoszcz', '+48730425938'),
('Andrzej', 'Szymański', '4105484949', 'Wrocław', '+48792827304'),
('Krzysztof', 'Nowak', '8262505579', 'Lublin', '+48957718896'),
('Jan', 'Jankowski', '6891279275', 'Kraków', '+48454449738'),
('Marek', 'Kamiński', '8274892155', 'Lublin', '+48680172628'),
('Piotr', 'Kowalski', '0998989447', 'Bydgoszcz', '+48722269549'),
('Marek', 'Kamiński', '2498829267', 'Łódź', '+48949115626'),
('Rafał', 'Wójcik', '5362617925', 'Kraków', '+48683585716'),
('Andrzej', 'Wójcik', '2164709327', 'Łódź', '+48255308064'),
('Marcin', 'Szymański', '9897186477', 'Szczecin', '+48101099170'),
('Monika', 'Jankowski', '2946385362', 'Szczecin', '+48864129302'),
('Marcin', 'Kamiński', '4505474281', 'Szczecin', '+48720980087'),
('Andrzej', 'Jankowski', '4031020473', 'Kraków', '+48100560068'),
('Maria', 'Mazur', '6064933904', 'Łódź', '+48407120811'),
('Jan', 'Kowalski', '1462937645', 'Wrocław', '+48725930188'),
('Joanna', 'Kamiński', '7456813286', 'Szczecin', '+48660491939'),
('Krzysztof', 'Szymański', '6021123645', 'Lublin', '+48423766617'),
('Ewa', 'Nowak', '2694499816', 'Łódź', '+48688940621'),
('Rafał', 'Szymański', '3625666685', 'Bydgoszcz', '+48186190697'),
('Anna', 'Wiśniewski', '6697923316', 'Szczecin', '+48382157680'),
('Anna', 'Jankowski', '6077583712', 'Gdańsk', '+48881819629'),
('Adam', 'Kamiński', '6676253851', 'Gdańsk', '+48379587557'),
('Joanna', 'Szymański', '1714479128', 'Gdańsk', '+48203279096'),
('Barbara', 'Wójcik', '2708642836', 'Katowice', '+48556602956'),
('Paweł', 'Wójcik', '5193409951', 'Wrocław', '+48276296769'),
('Jan', 'Kowalski', '0802837335', 'Poznań', '+48549670533'),
('Ewa', 'Kowalski', '5286520114', 'Szczecin', '+48566580705'),
('Joanna', 'Kaczmarek', '5345914862', 'Wrocław', '+48525211853'),
('Tomasz', 'Mazur', '4062778477', 'Łódź', '+48841080841'),
('Maria', 'Szymański', '0807272712', 'Gdańsk', '+48112874214'),
('Krzysztof', 'Kaczmarek', '1585004929', 'Kraków', '+48388370683'),
('Marek', 'Mazur', '0571187065', 'Szczecin', '+48223721888'),
('Rafał', 'Szymański', '8229101845', 'Łódź', '+48161977859'),
('Marcin', 'Kaczmarek', '7900992685', 'Wrocław', '+48638354683'),
('Ewa', 'Nowak', '1360241970', 'Szczecin', '+48128761098'),
('Marek', 'Kowalski', '8461122785', 'Kraków', '+48577950869'),
('Monika', 'Lewandowski', '8652468014', 'Łódź', '+48333252812'),
('Piotr', 'Jankowski', '0729714517', 'Szczecin', '+48275677696'),
('Maria', 'Wójcik', '7284356362', 'Warszawa', '+48406575122'),
('Marek', 'Kaczmarek', '0509223437', 'Lublin', '+48461050575'),
('Adam', 'Mazur', '9931466193', 'Łódź', '+48110321691'),
('Maria', 'Wójcik', '1628777744', 'Warszawa', '+48247421713'),
('Magdalena', 'Lewandowski', '2610661338', 'Szczecin', '+48690677405'),
('Barbara', 'Mazur', '6936822922', 'Kraków', '+48992591386'),
('Barbara', 'Lewandowski', '9635907032', 'Kraków', '+48852459533'),
('Tomasz', 'Kowalski', '6772195347', 'Katowice', '+48159863982'),
('Zofia', 'Jankowski', '7159422278', 'Łódź', '+48682913307'),
('Zofia', 'Mazur', '6124610992', 'Katowice', '+48618771696'),
('Barbara', 'Mazur', '0980486566', 'Katowice', '+48787354513'),
('Adam', 'Wiśniewski', '7267145097', 'Lublin', '+48479174298'),
('Andrzej', 'Lewandowski', '6876206617', 'Lublin', '+48519512581'),
('Barbara', 'Kamiński', '0837534330', 'Poznań', '+48688289542'),
('Barbara', 'Nowak', '8840247820', 'Bydgoszcz', '+48745723322'),
('Ewa', 'Wójcik', '0657435224', 'Katowice', '+48926311255'),
('Jan', 'Jankowski', '7498984359', 'Kraków', '+48383513746'),
('Zofia', 'Lewandowski', '3518048536', 'Szczecin', '+48883303157'),
('Magdalena', 'Kaczmarek', '3354610232', 'Katowice', '+48495837904'),
('Marcin', 'Szymański', '2555966521', 'Gdańsk', '+48316944867'),
('Agnieszka', 'Wójcik', '9126678034', 'Lublin', '+48816192021'),
('Krzysztof', 'Lewandowski', '9710435355', 'Katowice', '+48582144107'),
('Jan', 'Wójcik', '9651135651', 'Kraków', '+48247961052'),
('Marcin', 'Kaczmarek', '7839328069', 'Warszawa', '+48211756317'),
('Ewa', 'Nowak', '1829101534', 'Katowice', '+48110611202'),
('Piotr', 'Wiśniewski', '8839397215', 'Lublin', '+48918611822'),
('Jan', 'Wiśniewski', '0859033203', 'Katowice', '+48854382893'),
('Zofia', 'Kowalski', '4444063288', 'Warszawa', '+48576896084'),
('Adam', 'Wójcik', '2989390281', 'Bydgoszcz', '+48339996829'),
('Joanna', 'Kamiński', '5414837600', 'Gdańsk', '+48341466439'),
('Joanna', 'Wójcik', '0929510998', 'Kraków', '+48629712820'),
('Jan', 'Jankowski', '8482001669', 'Katowice', '+48481801890'),
('Ewa', 'Kowalski', '3563679354', 'Katowice', '+48296824703'),
('Marcin', 'Wiśniewski', '5901771529', 'Kraków', '+48281454070'),
('Anna', 'Lewandowski', '6859024036', 'Kraków', '+48268830031'),
('Magdalena', 'Wiśniewski', '4164494738', 'Łódź', '+48860045605'),
('Ewa', 'Kamiński', '5960749646', 'Gdańsk', '+48768248900'),
('Andrzej', 'Mazur', '6112242359', 'Łódź', '+48115802967'),
('Andrzej', 'Kowalski', '2432170733', 'Wrocław', '+48280022693'),
('Zofia', 'Kamiński', '2568800386', 'Poznań', '+48441230607'),
('Krzysztof', 'Wiśniewski', '0015122625', 'Kraków', '+48634539890'),
('Piotr', 'Lewandowski', '3157812249', 'Wrocław', '+48221195360'),
('Piotr', 'Szymański', '7608733719', 'Gdańsk', '+48123747855'),
('Anna', 'Wójcik', '2683762676', 'Poznań', '+48724132214'),
('Piotr', 'Lewandowski', '0590178463', 'Szczecin', '+48517000074'),
('Monika', 'Mazur', '6454243446', 'Poznań', '+48829975941'),
('Piotr', 'Wójcik', '7517219065', 'Poznań', '+48923514410'),
('Krzysztof', 'Jankowski', '9603947789', 'Katowice', '+48623234793'),
('Barbara', 'Wójcik', '6622000718', 'Wrocław', '+48602004619'),
('Zofia', 'Jankowski', '4117166576', 'Bydgoszcz', '+48257513391'),
('Jan', 'Jankowski', '2370412805', 'Wrocław', '+48975222774'),
('Rafał', 'Kowalski', '0367724041', 'Warszawa', '+48450398890'),
('Monika', 'Kaczmarek', '4136488134', 'Lublin', '+48494356550'),
('Adam', 'Lewandowski', '1648119819', 'Wrocław', '+48554295320'),
('Adam', 'Mazur', '1891191011', 'Gdańsk', '+48562411579'),
('Ewa', 'Mazur', '0572625076', 'Wrocław', '+48483385202'),
('Ewa', 'Szymański', '3378306120', 'Warszawa', '+48102197926'),
('Ewa', 'Nowak', '8855573212', 'Warszawa', '+48732014173'),
('Agnieszka', 'Kamiński', '6734759892', 'Bydgoszcz', '+48352400795'),
('Krzysztof', 'Mazur', '7069382541', 'Katowice', '+48456834205'),
('Tomasz', 'Szymański', '5446495067', 'Wrocław', '+48202222514'),
('Anna', 'Nowak', '7624648798', 'Kraków', '+48286658272'),
('Agnieszka', 'Mazur', '2637544070', 'Lublin', '+48300087059'),
('Jan', 'Nowak', '0703008815', 'Warszawa', '+48941924373'),
('Krzysztof', 'Kamiński', '6546105411', 'Bydgoszcz', '+48124188686'),
('Jan', 'Kaczmarek', '9376215505', 'Gdańsk', '+48139213545'),
('Piotr', 'Mazur', '8746475143', 'Wrocław', '+48285933289'),
('Krzysztof', 'Lewandowski', '9462887235', 'Szczecin', '+48897180504'),
('Adam', 'Kaczmarek', '3928344817', 'Gdańsk', '+48860053704'),
('Adam', 'Kaczmarek', '7427964185', 'Lublin', '+48770337904'),
('Maria', 'Lewandowski', '5184832502', 'Gdańsk', '+48814747823'),
('Marek', 'Szymański', '2394644057', 'Szczecin', '+48341845663'),
('Piotr', 'Wiśniewski', '6729233891', 'Wrocław', '+48851313824'),
('Ewa', 'Wójcik', '2677112764', 'Katowice', '+48656666406'),
('Barbara', 'Kamiński', '7059039036', 'Poznań', '+48501454642'),
('Tomasz', 'Wójcik', '9848912389', 'Wrocław', '+48610642052'),
('Jan', 'Nowak', '3080834335', 'Poznań', '+48564768149'),
('Andrzej', 'Wiśniewski', '2569083701', 'Szczecin', '+48614890727'),
('Piotr', 'Szymański', '9168925217', 'Wrocław', '+48102750620'),
('Jan', 'Kamiński', '6589939423', 'Gdańsk', '+48234314307'),
('Joanna', 'Kaczmarek', '0756628730', 'Kraków', '+48153548699'),
('Maria', 'Kaczmarek', '4747244398', 'Gdańsk', '+48825575487'),
('Marek', 'Kowalski', '0307819479', 'Poznań', '+48864137857'),
('Monika', 'Wiśniewski', '0558198812', 'Gdańsk', '+48557102829'),
('Marcin', 'Kaczmarek', '8126736015', 'Łódź', '+48189348569'),
('Rafał', 'Mazur', '5284194163', 'Łódź', '+48957806935'),
('Marcin', 'Mazur', '7542763687', 'Gdańsk', '+48835391371'),
('Rafał', 'Lewandowski', '7291504635', 'Szczecin', '+48594454737'),
('Jan', 'Szymański', '9535481523', 'Katowice', '+48598075887'),
('Jan', 'Kamiński', '5860600471', 'Kraków', '+48661828049'),
('Piotr', 'Kaczmarek', '1584928569', 'Wrocław', '+48744210247'),
('Magdalena', 'Nowak', '9850294556', 'Katowice', '+48648157997'),
('Jan', 'Kaczmarek', '8182881171', 'Katowice', '+48125077239'),
('Joanna', 'Kowalski', '9771017540', 'Kraków', '+48173652960'),
('Paweł', 'Jankowski', '4869588909', 'Łódź', '+48425550659'),
('Andrzej', 'Wiśniewski', '7279058491', 'Bydgoszcz', '+48592412217'),
('Andrzej', 'Nowak', '6849009211', 'Łódź', '+48175329727'),
('Adam', 'Kowalski', '8300251291', 'Katowice', '+48530700604'),
('Jan', 'Wójcik', '7146816721', 'Bydgoszcz', '+48586560236'),
('Marek', 'Szymański', '2361960057', 'Gdańsk', '+48653705840'),
('Magdalena', 'Kamiński', '7921779320', 'Katowice', '+48555430496'),
('Magdalena', 'Nowak', '8591424468', 'Wrocław', '+48640624344'),
('Katarzyna', 'Kamiński', '8199566638', 'Wrocław', '+48375319011'),
('Katarzyna', 'Wiśniewski', '3136973896', 'Warszawa', '+48243440296'),
('Marcin', 'Jankowski', '7713388981', 'Poznań', '+48234817038'),
('Barbara', 'Kaczmarek', '8976158844', 'Poznań', '+48950809833'),
('Andrzej', 'Wójcik', '5015777411', 'Wrocław', '+48759627009'),
('Rafał', 'Kaczmarek', '0365796787', 'Lublin', '+48813891160'),
('Maria', 'Kamiński', '4143170388', 'Szczecin', '+48307368163'),
('Monika', 'Kaczmarek', '5242775234', 'Kraków', '+48595032586'),
('Rafał', 'Nowak', '0621451955', 'Warszawa', '+48594236822'),
('Piotr', 'Kamiński', '4943901485', 'Wrocław', '+48439930318'),
('Barbara', 'Kamiński', '2330577184', 'Lublin', '+48639915523'),
('Zofia', 'Jankowski', '7685717044', 'Gdańsk', '+48555431137'),
('Magdalena', 'Jankowski', '2621148064', 'Szczecin', '+48557591450'),
('Jan', 'Kamiński', '5602547629', 'Gdańsk', '+48714225691'),
('Katarzyna', 'Kaczmarek', '9064184558', 'Katowice', '+48450927089'),
('Anna', 'Lewandowski', '3376155328', 'Wrocław', '+48131581347'),
('Rafał', 'Kaczmarek', '2208725825', 'Wrocław', '+48304932411'),
('Tomasz', 'Nowak', '1577763469', 'Kraków', '+48567528547'),
('Marek', 'Szymański', '9633641867', 'Katowice', '+48242877557'),
('Anna', 'Jankowski', '3082930798', 'Kraków', '+48125623940'),
('Paweł', 'Wójcik', '3523368931', 'Łódź', '+48638254550'),
('Andrzej', 'Lewandowski', '8535894685', 'Wrocław', '+48101273380'),
('Magdalena', 'Mazur', '9951491884', 'Łódź', '+48717693617'),
('Krzysztof', 'Mazur', '0601716203', 'Kraków', '+48604333606'),
('Andrzej', 'Kowalski', '0004896459', 'Lublin', '+48785374971'),
('Katarzyna', 'Nowak', '1798849660', 'Gdańsk', '+48873448528'),
('Anna', 'Wójcik', '7201000914', 'Łódź', '+48533927026'),
('Monika', 'Wójcik', '4086351628', 'Wrocław', '+48440931059'),
('Piotr', 'Szymański', '8974808601', 'Wrocław', '+48895630370'),
('Barbara', 'Kowalski', '8444175002', 'Gdańsk', '+48913259639'),
('Agnieszka', 'Wójcik', '1974660364', 'Gdańsk', '+48873545301'),
('Anna', 'Szymański', '4115013964', 'Szczecin', '+48809237377'),
('Anna', 'Lewandowski', '3842383668', 'Katowice', '+48745738961'),
('Ewa', 'Kowalski', '5736685772', 'Bydgoszcz', '+48228968030'),
('Monika', 'Wójcik', '7722406960', 'Kraków', '+48681394609'),
('Maria', 'Lewandowski', '4913556328', 'Kraków', '+48389119471'),
('Joanna', 'Nowak', '5433609246', 'Katowice', '+48345261489'),
('Rafał', 'Wójcik', '0096894311', 'Warszawa', '+48483476108'),
('Anna', 'Lewandowski', '9211403406', 'Wrocław', '+48877277422'),
('Maria', 'Wójcik', '5590031284', 'Kraków', '+48292342086'),
('Piotr', 'Szymański', '2035853125', 'Katowice', '+48652140510'),
('Zofia', 'Mazur', '0186140946', 'Poznań', '+48292152577'),
('Adam', 'Wiśniewski', '0164600705', 'Bydgoszcz', '+48927052117'),
('Piotr', 'Wiśniewski', '8941408131', 'Gdańsk', '+48843225307'),
('Magdalena', 'Jankowski', '1488684660', 'Bydgoszcz', '+48657279389'),
('Tomasz', 'Kowalski', '1032200691', 'Kraków', '+48627295320'),
('Anna', 'Szymański', '4847853650', 'Łódź', '+48740896671'),
('Andrzej', 'Wójcik', '5566719195', 'Lublin', '+48753342570'),
('Ewa', 'Kaczmarek', '6026579186', 'Warszawa', '+48899199211'),
('Agnieszka', 'Wiśniewski', '6300485390', 'Katowice', '+48970776008'),
('Katarzyna', 'Wójcik', '8823853152', 'Bydgoszcz', '+48883486137'),
('Magdalena', 'Kaczmarek', '1942376438', 'Warszawa', '+48349007185'),
('Marek', 'Kowalski', '5382993617', 'Kraków', '+48743510428'),
('Krzysztof', 'Nowak', '5027912951', 'Lublin', '+48303118751'),
('Maria', 'Mazur', '6771574602', 'Lublin', '+48191610764'),
('Paweł', 'Wiśniewski', '5603423001', 'Katowice', '+48455954680'),
('Marek', 'Wiśniewski', '5951048367', 'Lublin', '+48499043707'),
('Agnieszka', 'Mazur', '7360776006', 'Poznań', '+48461081366'),
('Marek', 'Wójcik', '7763580287', 'Szczecin', '+48726732985'),
('Magdalena', 'Kowalski', '5758595946', 'Łódź', '+48260520298'),
('Monika', 'Kamiński', '1295569720', 'Poznań', '+48733290066'),
('Ewa', 'Kamiński', '6897020954', 'Kraków', '+48639217420'),
('Zofia', 'Kamiński', '5375806554', 'Poznań', '+48680523616'),
('Ewa', 'Nowak', '5450648706', 'Kraków', '+48809188852'),
('Agnieszka', 'Nowak', '2354780508', 'Bydgoszcz', '+48955632882'),
('Joanna', 'Kamiński', '4321808418', 'Wrocław', '+48146253967'),
('Marek', 'Kamiński', '7927844327', 'Łódź', '+48723716418'),
('Magdalena', 'Lewandowski', '2496893692', 'Katowice', '+48955289302'),
('Ewa', 'Mazur', '0955121788', 'Lublin', '+48473637322'),
('Barbara', 'Jankowski', '8760038434', 'Kraków', '+48597561990'),
('Zofia', 'Kaczmarek', '2060321338', 'Wrocław', '+48691912591'),
('Anna', 'Jankowski', '2730098242', 'Szczecin', '+48510906642'),
('Andrzej', 'Kamiński', '0207560579', 'Warszawa', '+48817329397'),
('Maria', 'Lewandowski', '8366710602', 'Lublin', '+48586701096'),
('Rafał', 'Wójcik', '6766358807', 'Poznań', '+48828549127'),
('Agnieszka', 'Nowak', '2941552602', 'Katowice', '+48531054497'),
('Krzysztof', 'Lewandowski', '2863953213', 'Bydgoszcz', '+48728065177'),
('Anna', 'Nowak', '8920057928', 'Poznań', '+48598476523'),
('Tomasz', 'Wiśniewski', '0675923769', 'Gdańsk', '+48471699961'),
('Krzysztof', 'Jankowski', '8368419501', 'Warszawa', '+48535976365'),
('Piotr', 'Wójcik', '0248904549', 'Łódź', '+48733648915'),
('Rafał', 'Mazur', '6852912561', 'Lublin', '+48626011322'),
('Andrzej', 'Nowak', '7412269239', 'Lublin', '+48315700891'),
('Monika', 'Kowalski', '4887371338', 'Poznań', '+48995009670'),
('Magdalena', 'Kowalski', '0360926940', 'Gdańsk', '+48330848507'),
('Tomasz', 'Nowak', '2355564443', 'Łódź', '+48336292773'),
('Monika', 'Nowak', '3009821592', 'Bydgoszcz', '+48504621713'),
('Piotr', 'Jankowski', '7271405311', 'Gdańsk', '+48383219850'),
('Jan', 'Mazur', '4732759535', 'Poznań', '+48846104190'),
('Paweł', 'Kaczmarek', '6928597785', 'Warszawa', '+48984930828'),
('Krzysztof', 'Szymański', '7575854111', 'Szczecin', '+48117414992'),
('Joanna', 'Jankowski', '6932605370', 'Łódź', '+48417618539'),
('Anna', 'Kaczmarek', '0961731148', 'Warszawa', '+48491514694'),
('Zofia', 'Jankowski', '6404875326', 'Bydgoszcz', '+48888396679'),
('Joanna', 'Kamiński', '1335303758', 'Warszawa', '+48515691641'),
('Barbara', 'Wiśniewski', '8936714392', 'Łódź', '+48149473993'),
('Jan', 'Kowalski', '9993324603', 'Warszawa', '+48792558184'),
('Marcin', 'Wójcik', '1995126565', 'Szczecin', '+48599404628'),
('Marcin', 'Wiśniewski', '0329856489', 'Łódź', '+48491216612'),
('Zofia', 'Kamiński', '0428007878', 'Warszawa', '+48276363055'),
('Paweł', 'Szymański', '3483583931', 'Kraków', '+48580943052'),
('Piotr', 'Nowak', '4701250525', 'Lublin', '+48522300667'),
('Agnieszka', 'Kamiński', '2938599688', 'Poznań', '+48795282245'),
('Marcin', 'Wójcik', '4413416461', 'Kraków', '+48320079309'),
('Ewa', 'Kamiński', '5039177066', 'Lublin', '+48260721457'),
('Agnieszka', 'Jankowski', '0025640906', 'Katowice', '+48471461785'),
('Barbara', 'Lewandowski', '4912384582', 'Kraków', '+48233973205'),
('Katarzyna', 'Kamiński', '7646919726', 'Wrocław', '+48133608448'),
('Paweł', 'Jankowski', '9647443423', 'Gdańsk', '+48656059346'),
('Jan', 'Kamiński', '9570138851', 'Warszawa', '+48727093381'),
('Krzysztof', 'Wójcik', '3340876091', 'Bydgoszcz', '+48841871835'),
('Piotr', 'Wiśniewski', '7150027549', 'Szczecin', '+48203304152'),
('Adam', 'Szymański', '0382234533', 'Gdańsk', '+48379479207'),
('Jan', 'Wiśniewski', '5471928835', 'Lublin', '+48521847281'),
('Tomasz', 'Kamiński', '0351080263', 'Katowice', '+48747503610'),
('Zofia', 'Szymański', '0918802842', 'Wrocław', '+48854664751'),
('Adam', 'Mazur', '3849022587', 'Lublin', '+48200178432'),
('Andrzej', 'Nowak', '2803900371', 'Wrocław', '+48963482254'),
('Andrzej', 'Kowalski', '4860500291', 'Szczecin', '+48535189832'),
('Adam', 'Kowalski', '1494794443', 'Łódź', '+48384290968'),
('Krzysztof', 'Wójcik', '7271255163', 'Wrocław', '+48309666538'),
('Zofia', 'Mazur', '6201814434', 'Szczecin', '+48574999324'),
('Tomasz', 'Nowak', '4208925713', 'Bydgoszcz', '+48948286158'),
('Zofia', 'Mazur', '6512820144', 'Lublin', '+48263712600'),
('Marek', 'Kamiński', '1415192507', 'Szczecin', '+48385315174'),
('Magdalena', 'Nowak', '4427164436', 'Bydgoszcz', '+48112305561'),
('Marek', 'Kaczmarek', '6124864577', 'Wrocław', '+48404299115'),
('Paweł', 'Jankowski', '1882487657', 'Bydgoszcz', '+48882577032'),
('Katarzyna', 'Kaczmarek', '9457748396', 'Gdańsk', '+48958828233'),
('Andrzej', 'Mazur', '4742739139', 'Bydgoszcz', '+48603166171'),
('Paweł', 'Jankowski', '3176034511', 'Warszawa', '+48749497203'),
('Monika', 'Szymański', '5255778566', 'Poznań', '+48683891299'),
('Piotr', 'Wójcik', '1319634101', 'Łódź', '+48702746410'),
('Zofia', 'Mazur', '8214204850', 'Warszawa', '+48339853480'),
('Piotr', 'Mazur', '0500432227', 'Szczecin', '+48792690254'),
('Barbara', 'Mazur', '2335374036', 'Gdańsk', '+48511172026'),
('Andrzej', 'Wiśniewski', '5838052639', 'Bydgoszcz', '+48192542857'),
('Barbara', 'Wójcik', '9850113986', 'Łódź', '+48579565393'),
('Barbara', 'Wiśniewski', '0821528676', 'Łódź', '+48353394593'),
('Agnieszka', 'Kamiński', '9078132876', 'Łódź', '+48717959685'),
('Anna', 'Szymański', '7296774508', 'Łódź', '+48101425879'),
('Katarzyna', 'Wójcik', '3746666876', 'Szczecin', '+48440415069'),
('Adam', 'Kaczmarek', '4660979365', 'Warszawa', '+48238019990'),
('Adam', 'Szymański', '2029366043', 'Poznań', '+48830281363'),
('Barbara', 'Kowalski', '6743555488', 'Katowice', '+48597101965'),
('Magdalena', 'Szymański', '9572047394', 'Warszawa', '+48162266218'),
('Marek', 'Kaczmarek', '6729598081', 'Katowice', '+48396010071'),
('Magdalena', 'Nowak', '3478298446', 'Gdańsk', '+48789433970'),
('Anna', 'Nowak', '5606560990', 'Katowice', '+48812642912'),
('Anna', 'Lewandowski', '1847880062', 'Lublin', '+48959580831'),
('Paweł', 'Szymański', '9623639325', 'Wrocław', '+48770113614'),
('Marek', 'Wójcik', '5419888045', 'Bydgoszcz', '+48874836199'),
('Krzysztof', 'Kowalski', '4713212645', 'Szczecin', '+48466601171'),
('Krzysztof', 'Lewandowski', '3496907121', 'Katowice', '+48473134127'),
('Maria', 'Mazur', '7060036984', 'Bydgoszcz', '+48947513062'),
('Ewa', 'Wiśniewski', '0300825066', 'Gdańsk', '+48393997891'),
('Magdalena', 'Wójcik', '7848842952', 'Szczecin', '+48484365509'),
('Adam', 'Kaczmarek', '3558809401', 'Warszawa', '+48756357837'),
('Piotr', 'Jankowski', '8115546511', 'Wrocław', '+48315562856'),
('Magdalena', 'Mazur', '6678195280', 'Szczecin', '+48962296655'),
('Marcin', 'Kowalski', '0841109863', 'Lublin', '+48701298869'),
('Katarzyna', 'Kowalski', '8609356686', 'Katowice', '+48436123279'),
('Anna', 'Nowak', '6682222394', 'Łódź', '+48135563010'),
('Anna', 'Wiśniewski', '8082166166', 'Kraków', '+48995674372'),
('Magdalena', 'Mazur', '5125683888', 'Kraków', '+48285161784'),
('Andrzej', 'Nowak', '1600774123', 'Wrocław', '+48500721765'),
('Krzysztof', 'Kowalski', '0297985887', 'Warszawa', '+48664457483'),
('Andrzej', 'Kamiński', '3773254133', 'Wrocław', '+48651829854'),
('Paweł', 'Szymański', '0417972969', 'Kraków', '+48685506130'),
('Paweł', 'Wiśniewski', '5263929479', 'Warszawa', '+48318465669'),
('Ewa', 'Szymański', '5556154568', 'Łódź', '+48545037183'),
('Katarzyna', 'Wiśniewski', '7718393320', 'Warszawa', '+48624487299'),
('Monika', 'Mazur', '2560657990', 'Kraków', '+48432927565'),
('Anna', 'Nowak', '0437344580', 'Łódź', '+48306322604'),
('Tomasz', 'Nowak', '3768828117', 'Lublin', '+48162289000'),
('Anna', 'Mazur', '1091089350', 'Łódź', '+48336571070'),
('Krzysztof', 'Wiśniewski', '2601808333', 'Szczecin', '+48829348007'),
('Marcin', 'Wiśniewski', '7147517963', 'Bydgoszcz', '+48840229590'),
('Maria', 'Wiśniewski', '4524083748', 'Bydgoszcz', '+48330801189'),
('Agnieszka', 'Kowalski', '8375725172', 'Wrocław', '+48272042865'),
('Joanna', 'Jankowski', '6233352394', 'Lublin', '+48132985988'),
('Marek', 'Wójcik', '7606026033', 'Wrocław', '+48315799661'),
('Krzysztof', 'Jankowski', '5621432693', 'Katowice', '+48882659694'),
('Maria', 'Mazur', '4949441046', 'Wrocław', '+48345358579'),
('Barbara', 'Wójcik', '1894770824', 'Warszawa', '+48428706942'),
('Adam', 'Mazur', '4207839687', 'Łódź', '+48762431546'),
('Monika', 'Jankowski', '8229658580', 'Lublin', '+48571934291'),
('Katarzyna', 'Mazur', '0543106584', 'Bydgoszcz', '+48702304218'),
('Marek', 'Nowak', '6980062813', 'Szczecin', '+48850605094'),
('Barbara', 'Wiśniewski', '0773889128', 'Bydgoszcz', '+48735032665'),
('Tomasz', 'Mazur', '8862109349', 'Szczecin', '+48958138015'),
('Maria', 'Szymański', '2373718776', 'Bydgoszcz', '+48997109910'),
('Jan', 'Lewandowski', '5420316213', 'Wrocław', '+48772397857'),
('Zofia', 'Jankowski', '2726241426', 'Warszawa', '+48976752400'),
('Marek', 'Jankowski', '2552544419', 'Bydgoszcz', '+48270024073'),
('Katarzyna', 'Szymański', '1928769414', 'Wrocław', '+48270327893'),
('Piotr', 'Wiśniewski', '3059119747', 'Poznań', '+48312402422'),
('Rafał', 'Szymański', '1435254903', 'Kraków', '+48557679061'),
('Magdalena', 'Wójcik', '5755635572', 'Warszawa', '+48246936116'),
('Monika', 'Kaczmarek', '3205801572', 'Szczecin', '+48414973095'),
('Marcin', 'Mazur', '4968373699', 'Bydgoszcz', '+48760790327'),
('Magdalena', 'Kamiński', '6504574324', 'Warszawa', '+48524853440'),
('Piotr', 'Jankowski', '5168323753', 'Poznań', '+48277107738'),
('Ewa', 'Wiśniewski', '8844316830', 'Gdańsk', '+48146019628'),
('Joanna', 'Jankowski', '3458586440', 'Szczecin', '+48107544680'),
('Barbara', 'Szymański', '9366502070', 'Szczecin', '+48598566396'),
('Barbara', 'Mazur', '8260951664', 'Lublin', '+48561701420'),
('Jan', 'Lewandowski', '5584324139', 'Lublin', '+48506750500'),
('Monika', 'Szymański', '1756813062', 'Lublin', '+48665178442'),
('Andrzej', 'Szymański', '1411728603', 'Poznań', '+48524678556'),
('Katarzyna', 'Lewandowski', '5389531956', 'Łódź', '+48918921162'),
('Andrzej', 'Jankowski', '4777445423', 'Katowice', '+48760841896'),
('Agnieszka', 'Kowalski', '1804858288', 'Bydgoszcz', '+48109689337'),
('Joanna', 'Kamiński', '7496921578', 'Lublin', '+48255671943'),
('Maria', 'Kowalski', '0881116788', 'Szczecin', '+48972988073'),
('Jan', 'Nowak', '2559389767', 'Katowice', '+48968854447'),
('Magdalena', 'Nowak', '2103009508', 'Bydgoszcz', '+48631962277'),
('Agnieszka', 'Wójcik', '4524542346', 'Kraków', '+48143467714'),
('Katarzyna', 'Kaczmarek', '9733543586', 'Kraków', '+48586654328'),
('Maria', 'Kamiński', '8475440768', 'Katowice', '+48208786760'),
('Barbara', 'Wójcik', '5560194250', 'Gdańsk', '+48675322034'),
('Paweł', 'Kaczmarek', '9111001577', 'Lublin', '+48790284967'),
('Jan', 'Kamiński', '5387492187', 'Szczecin', '+48651305949'),
('Agnieszka', 'Wójcik', '1364918382', 'Szczecin', '+48643708446'),
('Ewa', 'Kowalski', '7261614820', 'Wrocław', '+48555877762'),
('Katarzyna', 'Kaczmarek', '9239960868', 'Szczecin', '+48277150909'),
('Maria', 'Wójcik', '9904805234', 'Poznań', '+48151223373'),
('Zofia', 'Jankowski', '1042770344', 'Kraków', '+48422254658'),
('Ewa', 'Lewandowski', '8653238478', 'Warszawa', '+48147504955'),
('Marek', 'Lewandowski', '5012445379', 'Wrocław', '+48794463068'),
('Jan', 'Szymański', '1581779501', 'Katowice', '+48677272291'),
('Rafał', 'Lewandowski', '6632843505', 'Kraków', '+48277365514'),
('Adam', 'Mazur', '1538572413', 'Wrocław', '+48196218558'),
('Krzysztof', 'Szymański', '0356392299', 'Lublin', '+48365471403'),
('Monika', 'Kowalski', '6851116546', 'Warszawa', '+48609801743'),
('Marcin', 'Kowalski', '8328819839', 'Poznań', '+48988660435'),
('Tomasz', 'Kaczmarek', '0257088955', 'Kraków', '+48848591289'),
('Andrzej', 'Mazur', '1317638353', 'Gdańsk', '+48970937937'),
('Joanna', 'Nowak', '9757529298', 'Bydgoszcz', '+48626331731'),
('Joanna', 'Mazur', '4070957980', 'Gdańsk', '+48346206609'),
('Magdalena', 'Kaczmarek', '3145903502', 'Katowice', '+48884345867'),
('Maria', 'Mazur', '6128389970', 'Kraków', '+48634934014'),
('Barbara', 'Jankowski', '6335798710', 'Łódź', '+48931295339'),
('Andrzej', 'Jankowski', '4130191329', 'Kraków', '+48304285158'),
('Katarzyna', 'Nowak', '6429277312', 'Katowice', '+48268740033'),
('Piotr', 'Wójcik', '1107892057', 'Bydgoszcz', '+48600663289'),
('Katarzyna', 'Jankowski', '0736552870', 'Lublin', '+48165862925'),
('Marcin', 'Kowalski', '1788309209', 'Kraków', '+48690863561'),
('Maria', 'Lewandowski', '0285013052', 'Katowice', '+48908696416'),
('Maria', 'Wójcik', '4058421552', 'Wrocław', '+48544584162'),
('Agnieszka', 'Nowak', '2030759944', 'Szczecin', '+48925940885'),
('Piotr', 'Kaczmarek', '1298388965', 'Poznań', '+48622418892'),
('Jan', 'Lewandowski', '0511372617', 'Łódź', '+48889020411'),
('Agnieszka', 'Mazur', '8813396358', 'Warszawa', '+48156252968'),
('Anna', 'Jankowski', '3712161878', 'Szczecin', '+48634745394'),
('Adam', 'Wiśniewski', '3279696051', 'Gdańsk', '+48418288519'),
('Marek', 'Mazur', '7646547281', 'Gdańsk', '+48279473659'),
('Marek', 'Lewandowski', '0689745883', 'Lublin', '+48544492875'),
('Joanna', 'Lewandowski', '9617632954', 'Kraków', '+48429704831'),
('Tomasz', 'Mazur', '5177358053', 'Warszawa', '+48919049362'),
('Piotr', 'Kowalski', '1363933387', 'Poznań', '+48832009493'),
('Joanna', 'Jankowski', '3899504872', 'Katowice', '+48741578742'),
('Katarzyna', 'Szymański', '1704210992', 'Bydgoszcz', '+48475791079'),
('Jan', 'Kaczmarek', '4267862433', 'Kraków', '+48986266820'),
('Anna', 'Mazur', '4671193958', 'Katowice', '+48438425433'),
('Marcin', 'Mazur', '3757766103', 'Łódź', '+48670341466'),
('Katarzyna', 'Kowalski', '3045123650', 'Poznań', '+48474938080'),
('Marek', 'Szymański', '2727257777', 'Lublin', '+48545195402'),
('Maria', 'Wiśniewski', '0578820882', 'Łódź', '+48401980368'),
('Krzysztof', 'Lewandowski', '6100318923', 'Poznań', '+48480503992'),
('Katarzyna', 'Jankowski', '1576249152', 'Kraków', '+48731157903'),
('Jan', 'Szymański', '4192849141', 'Kraków', '+48996432492'),
('Marek', 'Szymański', '9539618001', 'Poznań', '+48774175647'),
('Adam', 'Kaczmarek', '9290688703', 'Katowice', '+48455678640'),
('Adam', 'Lewandowski', '6865986155', 'Kraków', '+48740567172'),
('Rafał', 'Mazur', '1294089775', 'Łódź', '+48590620279'),
('Agnieszka', 'Kamiński', '1514560490', 'Lublin', '+48856260456'),
('Monika', 'Kaczmarek', '8535915324', 'Łódź', '+48316843144'),
('Katarzyna', 'Jankowski', '7050778836', 'Wrocław', '+48950009943'),
('Rafał', 'Kowalski', '1731508019', 'Lublin', '+48510735983'),
('Rafał', 'Kaczmarek', '6251752181', 'Gdańsk', '+48876585196'),
('Agnieszka', 'Jankowski', '4444837934', 'Warszawa', '+48622624172'),
('Rafał', 'Jankowski', '6080256041', 'Kraków', '+48603268415'),
('Maria', 'Szymański', '7714271364', 'Kraków', '+48791878721'),
('Joanna', 'Wiśniewski', '0355660066', 'Katowice', '+48223122230'),
('Marcin', 'Wójcik', '8253989323', 'Wrocław', '+48891482884'),
('Katarzyna', 'Nowak', '0007131940', 'Katowice', '+48980930140'),
('Adam', 'Szymański', '9303123223', 'Bydgoszcz', '+48274948915'),
('Anna', 'Wiśniewski', '9143923850', 'Warszawa', '+48108203411'),
('Tomasz', 'Lewandowski', '6230581451', 'Katowice', '+48509975931'),
('Anna', 'Szymański', '2641770522', 'Bydgoszcz', '+48998676208'),
('Agnieszka', 'Wójcik', '6018874118', 'Gdańsk', '+48731056752'),
('Magdalena', 'Lewandowski', '7225772032', 'Bydgoszcz', '+48912138661'),
('Rafał', 'Wójcik', '1792392603', 'Warszawa', '+48502149015'),
('Marcin', 'Kaczmarek', '4426557497', 'Wrocław', '+48704352870'),
('Barbara', 'Wójcik', '6373745926', 'Szczecin', '+48432990616'),
('Andrzej', 'Wiśniewski', '1947231275', 'Poznań', '+48360893970'),
('Magdalena', 'Jankowski', '7414558078', 'Katowice', '+48298268393'),
('Marcin', 'Kaczmarek', '1818471495', 'Kraków', '+48175263108'),
('Andrzej', 'Szymański', '5276286065', 'Katowice', '+48999543420'),
('Magdalena', 'Kowalski', '5629061436', 'Bydgoszcz', '+48875072142'),
('Katarzyna', 'Kamiński', '5207781108', 'Warszawa', '+48949238050'),
('Barbara', 'Lewandowski', '8109695692', 'Lublin', '+48410062570'),
('Magdalena', 'Wójcik', '6337469014', 'Kraków', '+48424076303'),
('Marcin', 'Mazur', '7153752751', 'Katowice', '+48817459489'),
('Piotr', 'Mazur', '6549462591', 'Gdańsk', '+48174026877'),
('Monika', 'Kaczmarek', '4608310122', 'Katowice', '+48149235537'),
('Jan', 'Lewandowski', '5638436751', 'Lublin', '+48790010645'),
('Zofia', 'Kaczmarek', '4893067384', 'Bydgoszcz', '+48591907551'),
('Adam', 'Kamiński', '1382013981', 'Katowice', '+48742701729'),
('Jan', 'Mazur', '4906849691', 'Wrocław', '+48422505176'),
('Adam', 'Szymański', '8597876235', 'Wrocław', '+48367201604'),
('Paweł', 'Kowalski', '8095583873', 'Poznań', '+48534643953'),
('Adam', 'Nowak', '7616072837', 'Lublin', '+48472983840'),
('Andrzej', 'Kaczmarek', '1145308049', 'Poznań', '+48328068064'),
('Agnieszka', 'Wójcik', '0161119350', 'Łódź', '+48896030148'),
('Paweł', 'Nowak', '4782477093', 'Poznań', '+48135936900'),
('Maria', 'Jankowski', '0879006198', 'Łódź', '+48269920517'),
('Ewa', 'Mazur', '5482592088', 'Warszawa', '+48116663236'),
('Krzysztof', 'Wiśniewski', '6689193841', 'Szczecin', '+48545347568'),
('Adam', 'Wiśniewski', '9646562687', 'Poznań', '+48500190127'),
('Andrzej', 'Kowalski', '7387758403', 'Bydgoszcz', '+48257078859'),
('Katarzyna', 'Kowalski', '0155203660', 'Szczecin', '+48460309264'),
('Joanna', 'Lewandowski', '7812522930', 'Katowice', '+48345600687'),
('Maria', 'Mazur', '9966099254', 'Szczecin', '+48764558601'),
('Monika', 'Nowak', '0608926592', 'Szczecin', '+48236517945'),
('Andrzej', 'Mazur', '3114223547', 'Katowice', '+48926457078'),
('Andrzej', 'Lewandowski', '9954419941', 'Kraków', '+48617596753'),
('Anna', 'Kowalski', '0133659412', 'Bydgoszcz', '+48363855439'),
('Adam', 'Wiśniewski', '9259654161', 'Lublin', '+48186367191'),
('Barbara', 'Wójcik', '2347803872', 'Łódź', '+48174288580'),
('Zofia', 'Mazur', '1568210992', 'Łódź', '+48708141042'),
('Krzysztof', 'Jankowski', '7005977573', 'Poznań', '+48889103612'),
('Jan', 'Kowalski', '1093198727', 'Gdańsk', '+48338971868'),
('Ewa', 'Kaczmarek', '2028998768', 'Poznań', '+48263676130'),
('Adam', 'Mazur', '4701882291', 'Łódź', '+48364057976'),
('Magdalena', 'Wiśniewski', '3866743632', 'Katowice', '+48128725323'),
('Zofia', 'Wiśniewski', '9464866212', 'Bydgoszcz', '+48619739182'),
('Piotr', 'Kowalski', '9424825109', 'Wrocław', '+48457651015'),
('Marek', 'Wójcik', '5690899195', 'Lublin', '+48797188250'),
('Katarzyna', 'Szymański', '1121199040', 'Warszawa', '+48944785172'),
('Krzysztof', 'Lewandowski', '1439349717', 'Szczecin', '+48519370444'),
('Adam', 'Kowalski', '7938145557', 'Bydgoszcz', '+48446266640'),
('Maria', 'Kaczmarek', '2777659346', 'Katowice', '+48474747508'),
('Paweł', 'Nowak', '3909272281', 'Gdańsk', '+48626937464'),
('Anna', 'Kowalski', '7964154014', 'Kraków', '+48519603579'),
('Marcin', 'Mazur', '5317119441', 'Gdańsk', '+48223709917'),
('Monika', 'Jankowski', '0454563986', 'Gdańsk', '+48203080828'),
('Tomasz', 'Lewandowski', '5683560301', 'Gdańsk', '+48433243555'),
('Marcin', 'Kowalski', '1552167873', 'Bydgoszcz', '+48851021482'),
('Ewa', 'Nowak', '9796095286', 'Warszawa', '+48661994269'),
('Maria', 'Wiśniewski', '5071008944', 'Szczecin', '+48355240445'),
('Anna', 'Kamiński', '2726784744', 'Lublin', '+48447884238'),
('Marek', 'Nowak', '6929580065', 'Kraków', '+48507365728'),
('Marek', 'Kowalski', '7131848939', 'Lublin', '+48261656419'),
('Zofia', 'Lewandowski', '9921806936', 'Łódź', '+48370082993'),
('Monika', 'Szymański', '8965425422', 'Poznań', '+48345182721'),
('Tomasz', 'Mazur', '8649001267', 'Kraków', '+48841845331'),
('Paweł', 'Wójcik', '4647108029', 'Kraków', '+48415682983'),
('Maria', 'Kowalski', '1738428864', 'Bydgoszcz', '+48581856266'),
('Adam', 'Kamiński', '0423870415', 'Lublin', '+48251026246'),
('Tomasz', 'Lewandowski', '0686671487', 'Kraków', '+48248730005'),
('Marcin', 'Wójcik', '7349517859', 'Poznań', '+48241489142'),
('Andrzej', 'Wójcik', '9268296577', 'Poznań', '+48919451079'),
('Ewa', 'Lewandowski', '4034575598', 'Lublin', '+48379959160'),
('Magdalena', 'Jankowski', '2799788220', 'Wrocław', '+48708238970'),
('Ewa', 'Lewandowski', '9117362816', 'Bydgoszcz', '+48493037282'),
('Paweł', 'Wójcik', '3631865465', 'Łódź', '+48728900667'),
('Adam', 'Lewandowski', '5708610595', 'Szczecin', '+48371007786'),
('Magdalena', 'Kowalski', '6957877314', 'Lublin', '+48676803543'),
('Paweł', 'Kaczmarek', '4929705689', 'Poznań', '+48759262099'),
('Anna', 'Szymański', '9867680992', 'Warszawa', '+48329793241'),
('Monika', 'Kaczmarek', '1083101198', 'Szczecin', '+48976387176'),
('Ewa', 'Wójcik', '6934284548', 'Katowice', '+48919750935'),
('Tomasz', 'Szymański', '4867700057', 'Łódź', '+48954373055'),
('Andrzej', 'Wójcik', '5933395213', 'Warszawa', '+48370947406'),
('Marcin', 'Lewandowski', '0269371151', 'Szczecin', '+48219183274'),
('Tomasz', 'Jankowski', '4015826297', 'Lublin', '+48782633488'),
('Jan', 'Lewandowski', '2121323445', 'Lublin', '+48758014079'),
('Jan', 'Kamiński', '9556053477', 'Katowice', '+48490627761'),
('Jan', 'Mazur', '9270980817', 'Gdańsk', '+48770289673'),
('Magdalena', 'Wiśniewski', '7903756152', 'Poznań', '+48289962194'),
('Monika', 'Wójcik', '4770182204', 'Bydgoszcz', '+48388848614'),
('Maria', 'Kamiński', '5172628720', 'Katowice', '+48714430087'),
('Marek', 'Jankowski', '0245360045', 'Gdańsk', '+48720702876'),
('Barbara', 'Szymański', '1656046054', 'Szczecin', '+48579235051'),
('Maria', 'Mazur', '3343076490', 'Szczecin', '+48303286961'),
('Marek', 'Jankowski', '6550747821', 'Gdańsk', '+48771664178'),
('Piotr', 'Mazur', '9198659797', 'Szczecin', '+48869342589'),
('Barbara', 'Nowak', '0409855512', 'Wrocław', '+48141893563'),
('Ewa', 'Nowak', '8205261004', 'Łódź', '+48204188428'),
('Katarzyna', 'Nowak', '8108428584', 'Szczecin', '+48573120909'),
('Adam', 'Kowalski', '4103172957', 'Katowice', '+48692430376'),
('Paweł', 'Kowalski', '1988506629', 'Warszawa', '+48349290053'),
('Adam', 'Szymański', '1261834119', 'Szczecin', '+48105021232'),
('Piotr', 'Kaczmarek', '4530360013', 'Poznań', '+48384155714'),
('Andrzej', 'Mazur', '6903219499', 'Łódź', '+48268479158'),
('Monika', 'Kamiński', '4598186062', 'Lublin', '+48882741290'),
('Joanna', 'Jankowski', '6629468402', 'Warszawa', '+48221909319'),
('Tomasz', 'Lewandowski', '6200550025', 'Katowice', '+48668540411'),
('Maria', 'Mazur', '6104442826', 'Łódź', '+48554533282'),
('Adam', 'Kaczmarek', '8887760413', 'Gdańsk', '+48338061593'),
('Marek', 'Nowak', '7568247175', 'Bydgoszcz', '+48607731237'),
('Ewa', 'Nowak', '2386286756', 'Wrocław', '+48677822720'),
('Krzysztof', 'Lewandowski', '7979573337', 'Kraków', '+48757424872'),
('Agnieszka', 'Nowak', '8698151320', 'Łódź', '+48447785529'),
('Zofia', 'Wiśniewski', '8881168304', 'Gdańsk', '+48628694866'),
('Piotr', 'Jankowski', '1585690207', 'Poznań', '+48627968167'),
('Andrzej', 'Kaczmarek', '8412261763', 'Katowice', '+48861487123'),
('Marek', 'Nowak', '7267622897', 'Poznań', '+48189809266'),
('Piotr', 'Wiśniewski', '2801903369', 'Szczecin', '+48301656466'),
('Joanna', 'Nowak', '8248289040', 'Katowice', '+48869256549'),
('Katarzyna', 'Lewandowski', '9850608348', 'Gdańsk', '+48181001881'),
('Maria', 'Szymański', '1833031808', 'Bydgoszcz', '+48731663624'),
('Jan', 'Jankowski', '1331309209', 'Gdańsk', '+48992276234'),
('Marek', 'Wójcik', '8142007683', 'Bydgoszcz', '+48626108593'),
('Ewa', 'Kaczmarek', '0034834158', 'Warszawa', '+48412919549'),
('Agnieszka', 'Lewandowski', '3995943250', 'Lublin', '+48134214119'),
('Jan', 'Kamiński', '9325649647', 'Poznań', '+48720444055'),
('Tomasz', 'Lewandowski', '5568463271', 'Warszawa', '+48476000228'),
('Paweł', 'Kamiński', '8690326545', 'Warszawa', '+48898142272'),
('Barbara', 'Lewandowski', '7498792346', 'Katowice', '+48775135535'),
('Adam', 'Mazur', '7122727169', 'Gdańsk', '+48583968120'),
('Anna', 'Kowalski', '3916266594', 'Bydgoszcz', '+48314869549'),
('Adam', 'Kamiński', '5377872937', 'Szczecin', '+48409003403'),
('Maria', 'Wójcik', '8349529296', 'Lublin', '+48397904275'),
('Monika', 'Kaczmarek', '1565106132', 'Warszawa', '+48488726690'),
('Barbara', 'Lewandowski', '3741019006', 'Katowice', '+48194454931'),
('Krzysztof', 'Wiśniewski', '3879758521', 'Szczecin', '+48586867930'),
('Krzysztof', 'Lewandowski', '1335638109', 'Warszawa', '+48921783643'),
('Paweł', 'Wójcik', '9737361769', 'Katowice', '+48811521739'),
('Piotr', 'Szymański', '0391058767', 'Warszawa', '+48171585488'),
('Marcin', 'Jankowski', '5194402143', 'Kraków', '+48364575703'),
('Maria', 'Kowalski', '5358935320', 'Gdańsk', '+48373733230'),
('Piotr', 'Kamiński', '3244592949', 'Wrocław', '+48226201485'),
('Agnieszka', 'Nowak', '8270134268', 'Katowice', '+48604891150'),
('Jan', 'Nowak', '3081455941', 'Katowice', '+48578891218'),
('Zofia', 'Kamiński', '3453412724', 'Łódź', '+48754371734'),
('Maria', 'Szymański', '9926910942', 'Warszawa', '+48396994318'),
('Anna', 'Wiśniewski', '3677022772', 'Katowice', '+48223778435'),
('Paweł', 'Kaczmarek', '2381162117', 'Gdańsk', '+48233249562'),
('Maria', 'Lewandowski', '7673985210', 'Szczecin', '+48379788684'),
('Andrzej', 'Lewandowski', '5909477089', 'Kraków', '+48357656938'),
('Krzysztof', 'Kowalski', '1202113425', 'Gdańsk', '+48241749335'),
('Piotr', 'Lewandowski', '8239943291', 'Kraków', '+48821487992'),
('Agnieszka', 'Lewandowski', '8805175620', 'Wrocław', '+48944651439'),
('Katarzyna', 'Kowalski', '1285733782', 'Kraków', '+48644964490'),
('Andrzej', 'Lewandowski', '8365443437', 'Kraków', '+48461953158'),
('Katarzyna', 'Wójcik', '7514357246', 'Kraków', '+48544522262'),
('Adam', 'Szymański', '6466225793', 'Lublin', '+48321211517'),
('Barbara', 'Szymański', '0204115010', 'Bydgoszcz', '+48245520230'),
('Jan', 'Kaczmarek', '9448823703', 'Kraków', '+48912729093'),
('Piotr', 'Kamiński', '9357417159', 'Łódź', '+48798748986'),
('Andrzej', 'Kamiński', '7516350929', 'Kraków', '+48953177967'),
('Piotr', 'Jankowski', '3229638589', 'Wrocław', '+48134389045'),
('Piotr', 'Lewandowski', '8616125127', 'Szczecin', '+48429059292'),
('Rafał', 'Jankowski', '1776063225', 'Gdańsk', '+48296606832'),
('Anna', 'Wiśniewski', '0964150096', 'Gdańsk', '+48265131258'),
('Adam', 'Lewandowski', '9774791485', 'Kraków', '+48855748712'),
('Barbara', 'Mazur', '3745188238', 'Warszawa', '+48530835173'),
('Ewa', 'Kowalski', '4040758352', 'Poznań', '+48565126053'),
('Jan', 'Lewandowski', '5822851985', 'Łódź', '+48235249852'),
('Paweł', 'Wiśniewski', '0419773017', 'Szczecin', '+48680025825'),
('Barbara', 'Kowalski', '3829011718', 'Warszawa', '+48480014594'),
('Katarzyna', 'Szymański', '7616434460', 'Katowice', '+48338626222'),
('Barbara', 'Kowalski', '5948408136', 'Szczecin', '+48175704452'),
('Monika', 'Mazur', '4155256110', 'Warszawa', '+48619748314'),
('Krzysztof', 'Lewandowski', '7120198321', 'Poznań', '+48186141050'),
('Paweł', 'Nowak', '1131418059', 'Gdańsk', '+48486835725'),
('Barbara', 'Szymański', '3767656444', 'Poznań', '+48234127312'),
('Adam', 'Kaczmarek', '6466625719', 'Lublin', '+48506877697'),
('Rafał', 'Kamiński', '0412389999', 'Wrocław', '+48685785820'),
('Katarzyna', 'Nowak', '3055549242', 'Lublin', '+48185464790'),
('Andrzej', 'Wójcik', '8228109751', 'Katowice', '+48450065392'),
('Andrzej', 'Mazur', '6979693869', 'Szczecin', '+48693399342'),
('Krzysztof', 'Jankowski', '1385934475', 'Bydgoszcz', '+48390751842'),
('Barbara', 'Wiśniewski', '0416850972', 'Łódź', '+48305850760'),
('Marek', 'Nowak', '7372078313', 'Łódź', '+48884776914'),
('Monika', 'Kaczmarek', '0288809858', 'Katowice', '+48921410383'),
('Maria', 'Nowak', '6371940348', 'Gdańsk', '+48770802212'),
('Andrzej', 'Wójcik', '1169997497', 'Warszawa', '+48428105774'),
('Anna', 'Kamiński', '8664031054', 'Kraków', '+48604268937'),
('Katarzyna', 'Jankowski', '7585356756', 'Lublin', '+48676401696'),
('Marek', 'Mazur', '4713963913', 'Bydgoszcz', '+48231855057'),
('Monika', 'Nowak', '6409251220', 'Gdańsk', '+48143341838'),
('Monika', 'Kowalski', '0285724480', 'Poznań', '+48720771085'),
('Tomasz', 'Nowak', '4681052107', 'Bydgoszcz', '+48307623672'),
('Barbara', 'Lewandowski', '1595244682', 'Bydgoszcz', '+48302869356'),
('Rafał', 'Nowak', '0702996813', 'Warszawa', '+48939523256'),
('Andrzej', 'Szymański', '0022376749', 'Szczecin', '+48876014005'),
('Joanna', 'Wiśniewski', '7940356252', 'Łódź', '+48778173032'),
('Joanna', 'Nowak', '1420410214', 'Lublin', '+48605488263'),
('Marcin', 'Jankowski', '5558151267', 'Gdańsk', '+48900523797'),
('Monika', 'Jankowski', '6428309730', 'Kraków', '+48785996592'),
('Paweł', 'Wójcik', '5372432667', 'Poznań', '+48230858519'),
('Adam', 'Szymański', '0813647483', 'Szczecin', '+48820803541'),
('Monika', 'Kaczmarek', '2402300384', 'Poznań', '+48702237448'),
('Krzysztof', 'Wójcik', '1320055819', 'Warszawa', '+48974428076'),
('Adam', 'Wójcik', '4238729493', 'Lublin', '+48831096288'),
('Marcin', 'Kowalski', '2246608551', 'Katowice', '+48251206685'),
('Tomasz', 'Kowalski', '6642720985', 'Lublin', '+48945346203'),
('Anna', 'Kaczmarek', '7551027528', 'Gdańsk', '+48624422992'),
('Zofia', 'Kowalski', '8212464630', 'Gdańsk', '+48328495805'),
('Ewa', 'Jankowski', '9578706396', 'Wrocław', '+48389303537'),
('Anna', 'Nowak', '7400832192', 'Gdańsk', '+48699791903'),
('Ewa', 'Szymański', '1108686322', 'Lublin', '+48743355770'),
('Zofia', 'Lewandowski', '7332239986', 'Łódź', '+48596950460'),
('Marcin', 'Mazur', '7674200507', 'Łódź', '+48946956659'),
('Andrzej', 'Nowak', '8368194495', 'Szczecin', '+48602490906'),
('Marcin', 'Jankowski', '6784444399', 'Gdańsk', '+48550820069'),
('Anna', 'Wójcik', '9769762214', 'Szczecin', '+48575424380'),
('Anna', 'Mazur', '4106513230', 'Wrocław', '+48128170053'),
('Ewa', 'Kowalski', '0678670474', 'Bydgoszcz', '+48582097735'),
('Marcin', 'Wójcik', '3099870143', 'Poznań', '+48545409130'),
('Magdalena', 'Wójcik', '7006903020', 'Kraków', '+48887197779'),
('Marek', 'Mazur', '2926725837', 'Warszawa', '+48653773675'),
('Maria', 'Mazur', '0677524344', 'Katowice', '+48340611584'),
('Piotr', 'Kamiński', '2175220127', 'Kraków', '+48235630948'),
('Tomasz', 'Nowak', '5091247597', 'Gdańsk', '+48168300137'),
('Maria', 'Kamiński', '6771684944', 'Bydgoszcz', '+48709919957'),
('Monika', 'Wójcik', '8218428604', 'Katowice', '+48179724514'),
('Barbara', 'Nowak', '6759091560', 'Gdańsk', '+48562352265'),
('Zofia', 'Wójcik', '5002941624', 'Lublin', '+48932746629'),
('Krzysztof', 'Kamiński', '8776745549', 'Wrocław', '+48317526058'),
('Andrzej', 'Wójcik', '2152048703', 'Łódź', '+48156000548'),
('Zofia', 'Jankowski', '1908080090', 'Bydgoszcz', '+48956056552'),
('Paweł', 'Lewandowski', '1663040893', 'Łódź', '+48909583719'),
('Rafał', 'Lewandowski', '9713180523', 'Poznań', '+48558712859'),
('Anna', 'Lewandowski', '3530743358', 'Poznań', '+48851235325'),
('Agnieszka', 'Wiśniewski', '6713360504', 'Bydgoszcz', '+48525682516'),
('Maria', 'Mazur', '2279711898', 'Katowice', '+48380186001'),
('Krzysztof', 'Mazur', '5524746923', 'Bydgoszcz', '+48295028903'),
('Monika', 'Kaczmarek', '3087949380', 'Katowice', '+48635944851'),
('Paweł', 'Kowalski', '3784538089', 'Szczecin', '+48983554788'),
('Jan', 'Jankowski', '7412108149', 'Łódź', '+48776809692'),
('Jan', 'Kaczmarek', '5813861537', 'Gdańsk', '+48194928152'),
('Andrzej', 'Kamiński', '6220880143', 'Poznań', '+48965410400'),
('Tomasz', 'Wiśniewski', '8080115931', 'Kraków', '+48558965634'),
('Anna', 'Lewandowski', '3794016266', 'Kraków', '+48726125214'),
('Magdalena', 'Mazur', '9693940940', 'Lublin', '+48343765402'),
('Barbara', 'Mazur', '4246001826', 'Katowice', '+48513172614'),
('Paweł', 'Wójcik', '1553992651', 'Wrocław', '+48803137595'),
('Andrzej', 'Mazur', '3304628655', 'Lublin', '+48492391791'),
('Agnieszka', 'Nowak', '1457927658', 'Gdańsk', '+48341276697'),
('Marcin', 'Mazur', '0675327729', 'Poznań', '+48208101139'),
('Joanna', 'Lewandowski', '0532635476', 'Katowice', '+48214436277'),
('Maria', 'Kaczmarek', '2950423400', 'Szczecin', '+48142685690'),
('Krzysztof', 'Wiśniewski', '5155741463', 'Szczecin', '+48557228043'),
('Barbara', 'Wiśniewski', '6941866758', 'Katowice', '+48522639580'),
('Paweł', 'Wiśniewski', '4995537473', 'Łódź', '+48214204402'),
('Ewa', 'Kowalski', '7441345798', 'Gdańsk', '+48216374003'),
('Zofia', 'Kaczmarek', '3662343168', 'Łódź', '+48332572107'),
('Andrzej', 'Kaczmarek', '7935232809', 'Kraków', '+48599398204'),
('Jan', 'Szymański', '0901728185', 'Kraków', '+48839707622'),
('Jan', 'Lewandowski', '7072007389', 'Szczecin', '+48341170515'),
('Joanna', 'Lewandowski', '1477139626', 'Wrocław', '+48702786555'),
('Barbara', 'Kamiński', '7094337770', 'Poznań', '+48165704548'),
('Andrzej', 'Nowak', '2695030123', 'Szczecin', '+48153168656'),
('Andrzej', 'Kowalski', '6430443815', 'Łódź', '+48726295555'),
('Piotr', 'Jankowski', '3725753763', 'Łódź', '+48827823714'),
('Paweł', 'Wójcik', '3523299857', 'Łódź', '+48161033155'),
('Magdalena', 'Kamiński', '5667482486', 'Łódź', '+48650131941'),
('Joanna', 'Lewandowski', '3380855450', 'Lublin', '+48452282809'),
('Tomasz', 'Kowalski', '7920995125', 'Wrocław', '+48791859830'),
('Katarzyna', 'Kaczmarek', '2814048232', 'Gdańsk', '+48995055225'),
('Marcin', 'Nowak', '3521811847', 'Warszawa', '+48705884746'),
('Jan', 'Wójcik', '7669350757', 'Kraków', '+48733296657'),
('Marcin', 'Wiśniewski', '5837607875', 'Kraków', '+48116469927'),
('Marcin', 'Kaczmarek', '7132909313', 'Wrocław', '+48135393966'),
('Rafał', 'Lewandowski', '6230134519', 'Poznań', '+48209942999'),
('Marcin', 'Kaczmarek', '9224686207', 'Katowice', '+48957257837'),
('Joanna', 'Kowalski', '5724342208', 'Lublin', '+48962447643'),
('Katarzyna', 'Kowalski', '9730827896', 'Poznań', '+48415407892'),
('Katarzyna', 'Wójcik', '5115786208', 'Kraków', '+48695685824'),
('Agnieszka', 'Lewandowski', '9630920236', 'Poznań', '+48600303709'),
('Jan', 'Kaczmarek', '5643729623', 'Łódź', '+48219456024'),
('Marek', 'Lewandowski', '4141509853', 'Warszawa', '+48733800211'),
('Paweł', 'Kowalski', '7900366323', 'Bydgoszcz', '+48262779416'),
('Maria', 'Jankowski', '7620504580', 'Poznań', '+48549387700'),
('Monika', 'Jankowski', '9095213000', 'Szczecin', '+48720701860'),
('Piotr', 'Lewandowski', '1216702925', 'Lublin', '+48854738402'),
('Krzysztof', 'Mazur', '5439250123', 'Poznań', '+48765791298'),
('Paweł', 'Szymański', '8342948957', 'Warszawa', '+48151028611'),
('Krzysztof', 'Jankowski', '5211745571', 'Gdańsk', '+48616509286'),
('Joanna', 'Szymański', '9180652566', 'Bydgoszcz', '+48982128541'),
('Anna', 'Wiśniewski', '1232821862', 'Katowice', '+48546026925'),
('Barbara', 'Szymański', '9120078294', 'Łódź', '+48743191273'),
('Rafał', 'Kamiński', '1521660141', 'Łódź', '+48293180926'),
('Marcin', 'Jankowski', '1032313477', 'Bydgoszcz', '+48106538983'),
('Agnieszka', 'Kamiński', '8458221716', 'Wrocław', '+48505279614'),
('Joanna', 'Szymański', '0600100656', 'Katowice', '+48980317866'),
('Piotr', 'Wójcik', '1592007897', 'Lublin', '+48763921703'),
('Zofia', 'Nowak', '6303580982', 'Kraków', '+48815777084'),
('Piotr', 'Lewandowski', '9685065113', 'Łódź', '+48724668881'),
('Maria', 'Lewandowski', '5721479614', 'Katowice', '+48683505711'),
('Anna', 'Wiśniewski', '6600450064', 'Poznań', '+48504679146'),
('Adam', 'Kowalski', '3228868877', 'Bydgoszcz', '+48439230414'),
('Agnieszka', 'Kaczmarek', '0081566778', 'Kraków', '+48395693227'),
('Adam', 'Kaczmarek', '2709189665', 'Lublin', '+48792675078'),
('Tomasz', 'Wiśniewski', '7776490587', 'Kraków', '+48208251351'),
('Magdalena', 'Nowak', '0899078110', 'Łódź', '+48262345009'),
('Barbara', 'Wiśniewski', '5595741554', 'Łódź', '+48195730580'),
('Maria', 'Jankowski', '0940463080', 'Poznań', '+48219352614'),
('Anna', 'Kamiński', '2882604122', 'Kraków', '+48994988356'),
('Marcin', 'Nowak', '1219167999', 'Wrocław', '+48154022335'),
('Paweł', 'Szymański', '3987046527', 'Lublin', '+48903323140'),
('Krzysztof', 'Mazur', '6974162447', 'Bydgoszcz', '+48158668196'),
('Tomasz', 'Jankowski', '6623416801', 'Szczecin', '+48628458498'),
('Marek', 'Wiśniewski', '4780200365', 'Kraków', '+48592207605'),
('Andrzej', 'Jankowski', '7495210741', 'Poznań', '+48718380377'),
('Maria', 'Jankowski', '1259666948', 'Szczecin', '+48929207182'),
('Jan', 'Kamiński', '7968629883', 'Wrocław', '+48302664276'),
('Paweł', 'Kaczmarek', '4031046439', 'Warszawa', '+48651799037'),
('Jan', 'Jankowski', '2834048509', 'Kraków', '+48347270797'),
('Jan', 'Kamiński', '3915412895', 'Warszawa', '+48718269817'),
('Rafał', 'Szymański', '7970486989', 'Łódź', '+48726091847'),
('Katarzyna', 'Wójcik', '1533483928', 'Lublin', '+48988754554'),
('Paweł', 'Lewandowski', '6340902649', 'Lublin', '+48571953112'),
('Jan', 'Szymański', '8704484183', 'Warszawa', '+48135998978'),
('Krzysztof', 'Kaczmarek', '6369907583', 'Kraków', '+48908518842'),
('Paweł', 'Wójcik', '6242759127', 'Poznań', '+48798262956'),
('Piotr', 'Mazur', '5905125997', 'Lublin', '+48723707409'),
('Katarzyna', 'Kowalski', '1258389716', 'Katowice', '+48503141793'),
('Zofia', 'Mazur', '1017059600', 'Bydgoszcz', '+48676151022'),
('Ewa', 'Mazur', '3992194242', 'Gdańsk', '+48115487584'),
('Anna', 'Wójcik', '3903933752', 'Kraków', '+48885708785'),
('Agnieszka', 'Jankowski', '2077611590', 'Warszawa', '+48842247053'),
('Marcin', 'Wiśniewski', '6078390963', 'Lublin', '+48540263331'),
('Marcin', 'Lewandowski', '2026893711', 'Bydgoszcz', '+48872779763'),
('Joanna', 'Jankowski', '7781016230', 'Bydgoszcz', '+48542695646'),
('Rafał', 'Kowalski', '8521239181', 'Kraków', '+48388644404'),
('Anna', 'Kaczmarek', '3390996668', 'Wrocław', '+48485830261'),
('Ewa', 'Nowak', '4653289866', 'Katowice', '+48827344710'),
('Marcin', 'Mazur', '8859959181', 'Katowice', '+48158848220'),
('Paweł', 'Wójcik', '6413691847', 'Szczecin', '+48593767065'),
('Adam', 'Mazur', '6894194397', 'Lublin', '+48492485123'),
('Piotr', 'Wiśniewski', '7638924613', 'Wrocław', '+48111493952'),
('Ewa', 'Wójcik', '3945123978', 'Bydgoszcz', '+48130817482'),
('Joanna', 'Kaczmarek', '3011588096', 'Poznań', '+48282094908'),
('Monika', 'Nowak', '0538111290', 'Wrocław', '+48809364434'),
('Magdalena', 'Nowak', '7103509674', 'Wrocław', '+48140753506'),
('Jan', 'Wójcik', '3225589825', 'Wrocław', '+48542639004'),
('Maria', 'Kaczmarek', '3154200538', 'Bydgoszcz', '+48543506460'),
('Paweł', 'Wójcik', '7373410811', 'Lublin', '+48110895212'),
('Ewa', 'Kowalski', '2060867068', 'Poznań', '+48491428863'),
('Andrzej', 'Kowalski', '2413062221', 'Kraków', '+48777731831'),
('Adam', 'Lewandowski', '9984192471', 'Wrocław', '+48552967284'),
('Ewa', 'Szymański', '7920353548', 'Katowice', '+48769218731'),
('Agnieszka', 'Kowalski', '1153657440', 'Wrocław', '+48449313375'),
('Krzysztof', 'Szymański', '5695312057', 'Lublin', '+48481819562'),
('Joanna', 'Wójcik', '2142821964', 'Poznań', '+48702426768'),
('Andrzej', 'Kamiński', '4570956769', 'Gdańsk', '+48949777649'),
('Tomasz', 'Lewandowski', '1611959747', 'Kraków', '+48780755288'),
('Jan', 'Mazur', '3094848275', 'Gdańsk', '+48635404754'),
('Maria', 'Nowak', '9387701546', 'Wrocław', '+48577966535'),
('Adam', 'Nowak', '8968474277', 'Poznań', '+48193309969'),
('Joanna', 'Wiśniewski', '4539757016', 'Bydgoszcz', '+48973712740'),
('Paweł', 'Kowalski', '1238939795', 'Wrocław', '+48372007312'),
('Ewa', 'Mazur', '3534894300', 'Katowice', '+48110204898'),
('Paweł', 'Kamiński', '4173089215', 'Poznań', '+48131560877'),
('Anna', 'Lewandowski', '1953482244', 'Łódź', '+48307646010'),
('Tomasz', 'Lewandowski', '0130580953', 'Bydgoszcz', '+48417001381'),
('Andrzej', 'Wiśniewski', '7387200113', 'Katowice', '+48575110519'),
('Agnieszka', 'Mazur', '2467934394', 'Poznań', '+48778509610'),
('Adam', 'Lewandowski', '6072361331', 'Lublin', '+48879003657'),
('Adam', 'Nowak', '4066361597', 'Szczecin', '+48116093907'),
('Agnieszka', 'Wójcik', '1074790678', 'Bydgoszcz', '+48904137736'),
('Marek', 'Szymański', '5242533127', 'Poznań', '+48164366800'),
('Marek', 'Kamiński', '5737233401', 'Kraków', '+48557756013'),
('Joanna', 'Wiśniewski', '7572177600', 'Szczecin', '+48311291127'),
('Tomasz', 'Nowak', '5164103043', 'Gdańsk', '+48138384064'),
('Maria', 'Kowalski', '9624861594', 'Wrocław', '+48337977510'),
('Rafał', 'Kowalski', '1960921285', 'Kraków', '+48931414601'),
('Paweł', 'Nowak', '3742565949', 'Bydgoszcz', '+48636519973'),
('Piotr', 'Kamiński', '5668735481', 'Warszawa', '+48408684246'),
('Tomasz', 'Lewandowski', '5724230793', 'Gdańsk', '+48618476493'),
('Barbara', 'Wiśniewski', '6513013864', 'Szczecin', '+48562225196'),
('Zofia', 'Mazur', '4281748804', 'Łódź', '+48570738892'),
('Krzysztof', 'Kamiński', '6245927865', 'Lublin', '+48772273294'),
('Joanna', 'Kowalski', '4246131134', 'Kraków', '+48699552758'),
('Jan', 'Kowalski', '4889939311', 'Szczecin', '+48374310009'),
('Agnieszka', 'Jankowski', '0369513418', 'Łódź', '+48525692687'),
('Rafał', 'Szymański', '1919190027', 'Warszawa', '+48733898326'),
('Magdalena', 'Mazur', '4714848890', 'Poznań', '+48124921222'),
('Piotr', 'Kaczmarek', '0040806983', 'Wrocław', '+48905812136'),
('Zofia', 'Kowalski', '2270787990', 'Wrocław', '+48934798994'),
('Zofia', 'Nowak', '1034120154', 'Poznań', '+48922667645'),
('Andrzej', 'Wiśniewski', '6666665075', 'Lublin', '+48233329368'),
('Agnieszka', 'Szymański', '6612715208', 'Lublin', '+48691935843'),
('Maria', 'Wójcik', '3113501516', 'Bydgoszcz', '+48233751064'),
('Barbara', 'Lewandowski', '1682186000', 'Szczecin', '+48772578559'),
('Marcin', 'Kamiński', '5843887273', 'Łódź', '+48672151918'),
('Marek', 'Wiśniewski', '7199934535', 'Gdańsk', '+48562637363'),
('Marcin', 'Mazur', '4773742449', 'Warszawa', '+48859447033'),
('Joanna', 'Wójcik', '0720669834', 'Łódź', '+48402069967'),
('Anna', 'Wójcik', '1663121008', 'Kraków', '+48798308453'),
('Marcin', 'Kamiński', '0213400195', 'Poznań', '+48441524200'),
('Magdalena', 'Kamiński', '4671650332', 'Katowice', '+48792140242'),
('Marcin', 'Kaczmarek', '1328166727', 'Lublin', '+48300870160'),
('Piotr', 'Kamiński', '4128214247', 'Warszawa', '+48391874948'),
('Joanna', 'Wójcik', '0002925634', 'Katowice', '+48919287212'),
('Agnieszka', 'Jankowski', '3483685788', 'Wrocław', '+48166080697'),
('Andrzej', 'Wójcik', '4266562963', 'Lublin', '+48979734430'),
('Jan', 'Kamiński', '9045785977', 'Gdańsk', '+48218536153'),
('Ewa', 'Nowak', '4630764904', 'Lublin', '+48824702606'),
('Rafał', 'Mazur', '1800374149', 'Bydgoszcz', '+48389691721'),
('Krzysztof', 'Jankowski', '3503524895', 'Lublin', '+48675888353'),
('Magdalena', 'Wójcik', '0877199736', 'Gdańsk', '+48376715318'),
('Ewa', 'Mazur', '4008264936', 'Wrocław', '+48742716211'),
('Paweł', 'Szymański', '3806973147', 'Kraków', '+48309964987'),
('Ewa', 'Kaczmarek', '8231989186', 'Warszawa', '+48131074825'),
('Katarzyna', 'Kaczmarek', '4618624114', 'Gdańsk', '+48173384473'),
('Maria', 'Mazur', '7701530424', 'Bydgoszcz', '+48751094322'),
('Monika', 'Kamiński', '7510468102', 'Lublin', '+48154964277'),
('Barbara', 'Kamiński', '0927274704', 'Lublin', '+48446624072'),
('Krzysztof', 'Mazur', '6260575869', 'Wrocław', '+48240485675'),
('Ewa', 'Szymański', '7847134262', 'Kraków', '+48636071940'),
('Andrzej', 'Jankowski', '8034390691', 'Gdańsk', '+48164264452'),
('Rafał', 'Jankowski', '0927687267', 'Warszawa', '+48573111227'),
('Barbara', 'Lewandowski', '0762458536', 'Łódź', '+48677096535'),
('Adam', 'Jankowski', '3448934021', 'Wrocław', '+48306177133'),
('Marcin', 'Nowak', '6736144797', 'Warszawa', '+48549738545'),
('Monika', 'Kamiński', '6966915090', 'Warszawa', '+48564160226'),
('Monika', 'Kowalski', '7558111800', 'Katowice', '+48296118399'),
('Adam', 'Kowalski', '8877556807', 'Katowice', '+48771276155'),
('Magdalena', 'Kaczmarek', '9369849906', 'Katowice', '+48598404573'),
('Piotr', 'Wójcik', '7477715361', 'Warszawa', '+48824490487'),
('Andrzej', 'Kowalski', '8895926863', 'Poznań', '+48381546896'),
('Katarzyna', 'Nowak', '9691289970', 'Bydgoszcz', '+48604470578'),
('Marcin', 'Jankowski', '9753436743', 'Lublin', '+48742942726'),
('Zofia', 'Kamiński', '2035050228', 'Katowice', '+48275303209'),
('Tomasz', 'Kaczmarek', '4139454273', 'Wrocław', '+48624760732'),
('Adam', 'Jankowski', '7827281967', 'Kraków', '+48427698495'),
('Magdalena', 'Mazur', '2399627130', 'Katowice', '+48383079296'),
('Monika', 'Lewandowski', '5436714144', 'Bydgoszcz', '+48731186520'),
('Rafał', 'Nowak', '8442481337', 'Gdańsk', '+48820200111'),
('Marek', 'Kaczmarek', '4913199377', 'Kraków', '+48840885996'),
('Anna', 'Kamiński', '3540024698', 'Katowice', '+48481820740'),
('Marcin', 'Mazur', '8452651991', 'Łódź', '+48272359910'),
('Monika', 'Wójcik', '8312138850', 'Szczecin', '+48174371542'),
('Marcin', 'Kowalski', '4174079937', 'Warszawa', '+48798412593'),
('Paweł', 'Jankowski', '9374656925', 'Gdańsk', '+48294832766'),
('Tomasz', 'Kamiński', '8979224579', 'Poznań', '+48430590358'),
('Piotr', 'Szymański', '4594839309', 'Bydgoszcz', '+48455625267'),
('Katarzyna', 'Wójcik', '8353084328', 'Szczecin', '+48586321125'),
('Andrzej', 'Kamiński', '1889748669', 'Lublin', '+48258586835'),
('Maria', 'Szymański', '3812846292', 'Poznań', '+48375780924'),
('Zofia', 'Wiśniewski', '2511499012', 'Bydgoszcz', '+48276181572'),
('Adam', 'Nowak', '2582241329', 'Łódź', '+48389726248'),
('Marek', 'Wójcik', '7086250889', 'Łódź', '+48485853588'),
('Marek', 'Jankowski', '1056630055', 'Kraków', '+48424421763'),
('Marcin', 'Nowak', '0187105827', 'Szczecin', '+48320503211'),
('Marek', 'Nowak', '5425014749', 'Warszawa', '+48107973794'),
('Barbara', 'Wójcik', '1605943278', 'Szczecin', '+48950557287'),
('Tomasz', 'Kaczmarek', '9368348151', 'Wrocław', '+48404331725'),
('Piotr', 'Kamiński', '4165950423', 'Katowice', '+48470209941'),
('Maria', 'Wiśniewski', '3186434436', 'Lublin', '+48876044864'),
('Joanna', 'Kamiński', '2252671736', 'Lublin', '+48827554316'),
('Paweł', 'Mazur', '7475257789', 'Wrocław', '+48580763273'),
('Katarzyna', 'Mazur', '2269257214', 'Lublin', '+48713757942'),
('Barbara', 'Kamiński', '1665653910', 'Poznań', '+48435137083'),
('Paweł', 'Lewandowski', '8731350707', 'Katowice', '+48359635066'),
('Rafał', 'Wójcik', '5256113997', 'Kraków', '+48814267704'),
('Paweł', 'Wójcik', '5999687677', 'Katowice', '+48467711397'),
('Paweł', 'Lewandowski', '9290144003', 'Bydgoszcz', '+48545842006'),
('Rafał', 'Kamiński', '5661916571', 'Wrocław', '+48538479498'),
('Ewa', 'Lewandowski', '9363202682', 'Wrocław', '+48678471341'),
('Magdalena', 'Kamiński', '5273200810', 'Warszawa', '+48744775797'),
('Marcin', 'Kaczmarek', '3425707667', 'Warszawa', '+48648340239'),
('Krzysztof', 'Wiśniewski', '8104568299', 'Poznań', '+48174567223'),
('Tomasz', 'Kowalski', '7571696195', 'Poznań', '+48301254017'),
('Katarzyna', 'Kowalski', '1905885684', 'Łódź', '+48161571359'),
('Agnieszka', 'Kaczmarek', '1801874354', 'Gdańsk', '+48700742278'),
('Agnieszka', 'Mazur', '6831202808', 'Gdańsk', '+48988359324'),
('Agnieszka', 'Jankowski', '9719979198', 'Bydgoszcz', '+48587563194') ;



INSERT INTO konta (id_klienta, numer_konta, saldo) values( 1, 34569201058039662829000513, 7763.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 2, 95478017392485032142952369, 9183.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 3, 54251030599515171114628398, 9835.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 4, 89013067576121979206556494, 2509.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 5, 47510017590005544460760725, 3122.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 6, 64554090469041091073818359, 8037.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 7, 45636346164961675121493598, 2177.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 8, 34590537999750016885518793, 6601.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 9, 94851255981106076433356968, 3302.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 10, 27598077913608292452973661, 9570.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 11, 89773803442426331567715391, 9668.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 12, 84855052444312873794974460, 4204.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 13, 90393193572844187611948728, 6287.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 14, 43047031105086420985066705, 9493.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 15, 68909369166510696505313184, 7794.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 16, 20017206383080000316959159, 5252.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 17, 14274671266957581551103516, 2236.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 18, 11432562350337606644016547, 4446.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 19, 35661328494670206673373165, 4716.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 20, 11834047882180879652099573, 2176.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 21, 43308015969298438412893004, 2778.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 22, 46530371101343298467878575, 3435.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 23, 29860162318045429665248359, 2704.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 24, 04743231490787789726515797, 1345.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 25, 28151606006834589223082875, 2459.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 26, 65442767769050629733787074, 6507.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 27, 46950478705253590252311291, 6813.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 28, 34644937342478242581491161, 1732.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 29, 10953291521345292448896783, 5707.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 30, 06671115243693498670287243, 2349.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 31, 36566854689528256240927896, 4177.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 32, 27594056126113286006096059, 3593.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 33, 57482309178178701306004641, 604.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 34, 16198294438340064667283520, 800.39);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 35, 79409195675494486797518878, 9293.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 36, 42486598562547849895632554, 6063.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 37, 74551320747331973865063109, 9690.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 38, 54510840779256152401627957, 9380.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 39, 53704671782762699935051497, 4382.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 40, 51154176003066739699931949, 4132.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 41, 65672285314154628236314316, 9270.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 42, 54108046725555176344341321, 3031.39);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 43, 48030171889339383486293906, 9765.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 44, 38545253351335682805393198, 6248.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 45, 67704704647142345842786160, 3615.46);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 46, 64769388050867907439094753, 7256.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 47, 18086905883504872041640748, 5295.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 48, 08496336196260426995498911, 218.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 49, 39158359772300176994949770, 5331.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 50, 93509425087136329919637683, 1254.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 51, 89319541819973021890763664, 9036.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 52, 22547212457928624435444433, 184.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 53, 96037442746549807259932720, 6801.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 54, 10892652791411081549679609, 6593.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 55, 75016395384254819333274043, 4860.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 56, 56153670980639600664255727, 1458.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 57, 24135756653401165267010605, 8857.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 58, 63094601011604624002977086, 5878.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 59, 51163923357940715547099144, 9420.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 60, 18675999182339760810568447, 9191.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 61, 12195467144884136263441440, 8378.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 62, 50278284391794509640408319, 3126.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 63, 78273862267089405986315282, 9756.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 64, 89505034138141508117005340, 9814.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 65, 28245961159161308745134997, 9730.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 66, 92028768537939366196269127, 2431.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 67, 86723354787475268456840152, 1963.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 68, 43284987863208030783089206, 1405.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 69, 81196560267486981658276559, 7904.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 70, 58658958958446260313404835, 2176.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 71, 74430056271655277674187101, 5401.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 72, 69069507145621732762604185, 5132.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 73, 36886204750734840253165391, 5492.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 74, 04595953225217035888591318, 7097.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 75, 23651468852920144772704420, 4755.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 76, 80078201731278726560915972, 5618.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 77, 77761374664236091485413169, 1980.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 78, 91375211932815376334265702, 2487.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 79, 61158153198280898952455126, 4249.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 80, 23282803058477971356116402, 2381.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 81, 35921108035450537897771285, 3495.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 82, 98788938062482792845650300, 107.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 83, 88065979797927881259237848, 6314.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 84, 51118571518063639668295290, 2973.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 85, 10616030067541252961076183, 3173.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 86, 92685928890893254816075914, 6851.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 87, 26533342990400850231288705, 9189.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 88, 95684095562571190914358216, 8881.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 89, 02531674220977920762526319, 7061.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 90, 14637301190872911696503198, 5118.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 91, 86714225144065126304474691, 6665.59);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 92, 35387241702262142481725856, 6967.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 93, 44958410172156540556436757, 2789.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 94, 61296200386101443261671799, 1484.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 95, 34669139148983829014794556, 148.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 96, 16861380862995421193544621, 7072.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 97, 38823669622145452604945843, 5476.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 98, 11391696467778139750550056, 8139.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 99, 83870240289523836627127599, 103.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 100, 42217378049269442726687952, 8985.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 101, 58766291830915246679973245, 3634.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 102, 89853220086896632098835595, 7721.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 103, 03956709413237754530567490, 7488.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 104, 83048287555641411558261515, 4513.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 105, 03647966109188290870025137, 5070.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 106, 34185600353985803878369556, 7528.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 107, 67745391398775782695068137, 6894.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 108, 76106156285208451519536652, 2760.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 109, 17737291350511431090278259, 22.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 110, 92339942703522883671919572, 948.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 111, 09867233699335016650631627, 4143.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 112, 48312799569997311590616422, 6653.46);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 113, 34324940919819900169988649, 5369.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 114, 67453816537677161520617930, 2301.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 115, 06011119974146206918790244, 6036.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 116, 33227468783515688441283804, 2687.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 117, 49729421285073339912755486, 2230.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 118, 76861294365508446976056434, 2739.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 119, 76236112760085931101837914, 714.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 120, 37950813958277837416166608, 8525.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 121, 29615038997392658126772061, 7406.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 122, 74076025912649925195660902, 5524.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 123, 06073032852430466827349584, 802.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 124, 67363285178107230933698426, 7205.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 125, 57726243521849331529244436, 2045.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 126, 33039770375742478943675003, 7023.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 127, 64195481897047858145932536, 4841.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 128, 10823354079501308636637169, 278.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 129, 02864648003304003936773572, 6484.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 130, 46942962750765794498750853, 6451.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 131, 84918447452967050221154067, 432.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 132, 38911702640354607248417526, 945.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 133, 81758876830480846442860772, 9986.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 134, 51909981493206582177191475, 4544.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 135, 30544725304391684813096467, 132.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 136, 25549338504607720719646064, 9955.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 137, 23305743286466458293332298, 1109.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 138, 06642385479461817650462968, 1155.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 139, 49708778014561008170855439, 2902.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 140, 32228406801053926957168679, 2588.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 141, 65089893756148728552313682, 844.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 142, 27145053101392612998114577, 2237.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 143, 14972925435410355266807959, 1699.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 144, 61908274427828282715232331, 715.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 145, 50135777696334320852353930, 1287.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 146, 60235044733783133582234389, 6364.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 147, 85707353190926056340830238, 459.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 148, 66036300925800521489333255, 4238.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 149, 45525098189475743188719527, 9845.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 150, 19855200850302469509308465, 1088.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 151, 37951311356847754195847559, 6157.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 152, 14615395767356695216363669, 5301.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 153, 15149075347634481413828141, 1299.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 154, 27551442853736055715636045, 8390.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 155, 11363614071074174260770755, 8552.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 156, 14299951547770025911607258, 351.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 157, 65457164738416380433681287, 2019.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 158, 34341338942372070103489860, 5503.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 159, 33155128776065712799279368, 3324.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 160, 47447060302697401857115027, 7114.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 161, 28365799914605070258192703, 5857.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 162, 43795981063956361276801140, 1433.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 163, 43523965851487146476795043, 2438.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 164, 25748619416413569623337924, 4966.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 165, 58328961881397062922721412, 2830.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 166, 81471399160281101536647275, 9475.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 167, 69566819784395561505374764, 54.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 168, 82380892911715609317241853, 9138.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 169, 35544090535764012470069022, 9481.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 170, 90248954803658827807238460, 2044.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 171, 45839899330659280013475606, 2267.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 172, 44200927180441637588371753, 2781.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 173, 10873012874057556266957778, 7552.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 174, 66397302578335065682875531, 2116.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 175, 99409245194031934840343846, 9171.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 176, 02817768246548645762795917, 2245.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 177, 71091417700157911444212753, 9891.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 178, 86574082828324886101411971, 1896.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 179, 77317258953320421614079217, 3535.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 180, 69589113773199890147565781, 842.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 181, 12298185645746787367698293, 1888.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 182, 71411309388215423540951821, 425.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 183, 91765559942468888083801564, 5005.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 184, 23173317051186194056741684, 9659.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 185, 06462640656073137411098953, 6310.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 186, 21388154809513415354260929, 7781.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 187, 75874828950487676854900048, 2172.59);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 188, 86492693159936938399495490, 1318.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 189, 29887571233913775464423456, 3045.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 190, 94538001873424467411749983, 988.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 191, 06627128370382641225489784, 7851.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 192, 04034967519269391304984363, 2491.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 193, 31920248349338843428820314, 9467.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 194, 03902281932961439985609525, 4379.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 195, 72341905056600958756171723, 5608.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 196, 58306000381308726531458512, 1497.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 197, 65591187944684814608184685, 5272.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 198, 03901859507000031677141796, 1043.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 199, 82373003859041081236820384, 9508.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 200, 17613481370530855470517234, 4206.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 201, 97814459267248394213452745, 3290.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 202, 62087311219218694716468759, 5954.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 203, 46482652484009309967020464, 13.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 204, 64863405544376599696541314, 1018.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 205, 86659020430369241568981994, 6017.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 206, 81561496854105474544014877, 4647.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 207, 26997414463075439873459378, 6049.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 208, 61589495804973170355108602, 6156.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 209, 07180348213399644560722200, 1515.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 210, 66198813073781674522010312, 1889.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 211, 86402362489556297962189271, 289.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 212, 50897256629024797095896594, 7411.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 213, 38258877726926343241286264, 8696.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 214, 90646667848622543171643256, 2048.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 215, 19896314988494828665427858, 6746.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 216, 10090437030962648222761527, 6509.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 217, 98539823365881130787466071, 1078.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 218, 34143949414275525934632461, 2226.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 219, 01141704175389625890512411, 1148.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 220, 19777937163708863330855025, 554.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 221, 93803972735443187014825483, 6532.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 222, 33202627684556965896075688, 4774.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 223, 19065221059994585839158655, 2375.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 224, 91355054441997801780964087, 6857.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 225, 94430737090616197131618964, 7650.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 226, 46371608420604329904392400, 6587.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 227, 71550373172351800249399926, 9432.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 228, 41173505551946432360372332, 5448.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 229, 10388630093719371344724685, 3183.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 230, 98716317687261255034903515, 544.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 231, 91016570077865725946204309, 7983.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 232, 18074035388292989080739046, 8375.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 233, 44487575696953240072656607, 1176.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 234, 77876124041463608923038277, 6949.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 235, 83716977104979833434927471, 7324.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 236, 78637786054728582723102339, 2213.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 237, 23209113544421845775723478, 9343.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 238, 28047188721014147560366303, 3896.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 239, 26012127388886336537167053, 1820.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 240, 89604565693351732187397284, 128.13);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 241, 11867809289198397038238060, 4800.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 242, 90045912580528797109219338, 5944.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 243, 90911802237587058698966237, 207.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 244, 56903729459754663791967422, 8857.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 245, 21109994183297481460297553, 1677.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 246, 89730502654911419099871936, 20.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 247, 25640713760461326713480028, 868.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 248, 66918679534104377564711539, 3533.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 249, 51058432888696450143259521, 1474.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 250, 10127673202015589631335087, 8555.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 251, 09082031813010718540620782, 2202.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 252, 81310791715848551077943180, 203.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 253, 06861167056134519033201640, 2816.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 254, 81807510170874670574591999, 925.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 255, 87758303180923370478220614, 1920.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 256, 37408875359765731497109507, 5123.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 257, 69687742219544118043944914, 1814.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 258, 54363568967138061679598823, 2119.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 259, 25678998822754226389145218, 6165.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 260, 99051989998092249750143562, 1732.46);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 261, 81239031191294397958356851, 2434.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 262, 39828278446869193197169976, 4810.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 263, 50081339908531851849357901, 2200.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 264, 86185063626458075817461586, 6557.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 265, 03995512876070940831807342, 3476.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 266, 04157360547507267900593839, 1861.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 267, 00176070775441920886830935, 1992.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 268, 00070218058563389443504190, 6813.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 269, 76766163960097354552650875, 6169.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 270, 79795276807464172961179422, 1157.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 271, 55218676560187417105537936, 3203.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 272, 61467469750940269395903335, 4610.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 273, 23362452660404453943782359, 2851.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 274, 35649099320674430377696353, 2587.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 275, 17422782785597279048045801, 10.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 276, 86171053879899591485880867, 2860.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 277, 29569495842815291930286940, 8399.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 278, 18648179073597954524981607, 5636.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 279, 10233950960053521979404262, 9627.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 280, 41253278115167543910100914, 8409.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 281, 71255965046908877458540073, 7836.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 282, 64427812943713614485702388, 5297.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 283, 34312137632558245912472499, 4820.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 284, 42828209122905162054567075, 713.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 285, 75108274342988741916640032, 5002.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 286, 19169616726860310515510190, 737.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 287, 95913686241118356674165985, 5974.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 288, 66340151261593804819606626, 4971.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 289, 46392614580886079941945580, 9527.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 290, 23993188003852032691445994, 2273.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 291, 35527050320606972915824086, 2527.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 292, 36107940334696719797782284, 3566.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 293, 76387944940536990994256751, 3363.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 294, 82224621530781154456510953, 2370.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 295, 08813084948513398285939602, 7181.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 296, 90785509106124713261835908, 3664.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 297, 14130264286689414497161152, 6060.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 298, 19537124950899805177725011, 6449.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 299, 10868531378576371021590642, 5201.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 300, 78010103587140530013441448, 6961.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 301, 85587484690524752787673587, 6833.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 302, 92855324676729285552783960, 7727.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 303, 33275559247474296763271877, 2456.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 304, 35784087241266245567237591, 1744.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 305, 82204858000618808511445519, 8770.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 306, 44754197658813137144417969, 5883.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 307, 25099005582454292135804388, 9186.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 308, 62803482267393381732680767, 7099.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 309, 10463330814744876323703432, 7502.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 310, 24388056078824876482104382, 194.39);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 311, 48203768742874274011167236, 9743.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 312, 17765667882151629330392598, 6051.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 313, 75898631584707589278757623, 6035.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 314, 20195190389412239055157112, 3749.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 315, 16089708944367125640942906, 1260.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 316, 20146887194208279976625553, 6996.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 317, 98310961295243751759274538, 1728.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 318, 25320743530726783640919848, 8274.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 319, 23046276601449345538741155, 8489.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 320, 82313531663365931509991703, 4080.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 321, 91269828187219694717655323, 9429.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 322, 96949812709262657549623532, 5576.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 323, 85609435236830370579331738, 773.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 324, 78243327259593919262995366, 324.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 325, 89215724354630362348848224, 4608.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 326, 80984108713429266331139834, 4518.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 327, 70409046255409796604463058, 6879.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 328, 00033712247109947700741969, 144.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 329, 63852811184820512215874269, 2033.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 330, 84216880157965420054532288, 4779.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 331, 25291550781349846673765100, 4742.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 332, 94672811002885298451757871, 5875.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 333, 75760720669611222373982504, 7206.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 334, 61561232234009270137736269, 4903.59);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 335, 29029304135372111706985991, 9066.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 336, 01980840363777732392025065, 1979.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 337, 42299441681588241678610871, 8431.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 338, 95373623812357971392252996, 4360.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 339, 18982572646908824122334070, 7224.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 340, 95859845763016547367987104, 9256.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 341, 78481672220982205431729688, 2090.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 342, 99959716855240190835126177, 525.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 343, 41707019986690291615270998, 703.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 344, 08876152845871583170411471, 6905.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 345, 91061131304003496109824768, 1942.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 346, 57858637966337828809341741, 7973.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 347, 27479748253723578667553955, 1008.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 348, 89488793533413414936287968, 9501.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 349, 42367406945989147207221022, 6099.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 350, 48476565724232581093764036, 9296.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 351, 92253944745055683312620203, 4489.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 352, 99136249149853824901413826, 7362.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 353, 43319998852473936844420502, 4624.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 354, 33790567207658046349316442, 1627.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 355, 45658984716468067162242373, 4857.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 356, 32816626463392899613833048, 5224.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 357, 72981945505650659788888364, 6507.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 358, 50105640510566228536980232, 5319.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 359, 20147116219293175698647725, 783.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 360, 46647196710269428920126150, 909.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 361, 58915061399683530473198155, 35.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 362, 71342718562176630321741143, 914.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 363, 14269253440204452402967577, 4569.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 364, 02608134955457145444662928, 5698.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 365, 16953025790110660749582340, 392.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 366, 42411774685986889921442119, 6747.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 367, 63474709475707591264265456, 9752.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 368, 99705890338219379988190289, 228.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 369, 21417509457595252141291039, 7704.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 370, 41482743967350412167497964, 4850.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 371, 88753291723257595617145142, 6378.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 372, 19647872839702319360908334, 4242.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 373, 01736376618857398814542830, 8035.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 374, 63399277689994906419127095, 2389.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 375, 71189129540797593707325067, 4765.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 376, 50102508305195262812739085, 5885.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 377, 96286687549206760127039099, 1431.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 378, 53269747730914411584440956, 2034.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 379, 63279551707778931118268080, 786.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 380, 93443133938358958636137507, 370.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 381, 33579631020267392856696136, 1220.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 382, 60361630494124956307524908, 634.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 383, 89782734035958912239574007, 694.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 384, 55347483522881574690660927, 2497.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 385, 79121505627441493113114503, 984.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 386, 21901099962204723090396866, 3420.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 387, 37230993349601682246391647, 2570.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 388, 18444026536281834309408710, 3176.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 389, 67862949468070601797832891, 7698.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 390, 14661780719012940233025990, 6069.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 391, 04674390784167584229362292, 3915.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 392, 50355781217401905345893431, 3639.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 393, 16061084117128570275963252, 402.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 394, 48837892215714469083468614, 3382.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 395, 63801430385849459298996791, 4169.13);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 396, 88721794393760823144574373, 4109.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 397, 21210033993500379821075569, 5031.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 398, 77805416347776094094404229, 1789.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 399, 92020574651880495390817988, 9540.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 400, 22597689134822070066762938, 6937.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 401, 09249850220489734676613942, 6927.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 402, 87482734928404622338492301, 3113.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 403, 27644281283346085343819412, 3369.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 404, 19835376175254979579383521, 2505.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 405, 29750286987271282153358243, 8441.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 406, 43921285729390149422853384, 9849.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 407, 48868698122895950943011588, 8648.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 408, 78825416524030252980638229, 7901.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 409, 26633177903374583018222596, 4837.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 410, 60950596847842300120813405, 1693.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 411, 15085657926811366319533439, 2848.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 412, 40518251771869174511117914, 2820.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 413, 60232912848073781586883224, 193.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 414, 29499852808332090928756141, 6354.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 415, 80108359956255877735881313, 9360.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 416, 62285117685119424898688084, 9932.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 417, 93859794497709536472374529, 1613.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 418, 30918684632640774883609712, 553.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 419, 57205243706770567911076797, 5095.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 420, 75699709228064068988426234, 1861.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 421, 36167271775438545266926590, 1287.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 422, 49947914825568825290776506, 8064.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 423, 12573487962787351097921775, 228.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 424, 35399005654533264137872051, 6014.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 425, 22078766789695302079721653, 9006.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 426, 63687928104103293279462994, 9015.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 427, 95715191425986697814240506, 8566.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 428, 70081751660496493877832601, 1558.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 429, 52082334004142993374050479, 1458.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 430, 65801354255647347161986859, 6859.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 431, 38083096154551711612235617, 2380.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 432, 91867097385242436302556574, 4251.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 433, 80509553834520649046617346, 4738.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 434, 77131371451839835795635129, 8749.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 435, 29757612404649302053254735, 7685.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 436, 33723807339742969354325473, 8957.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 437, 78223755370364180430089318, 9180.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 438, 83429323827847507966404846, 4203.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 439, 58700725168514289059340309, 1840.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 440, 76021944250944589668304261, 3403.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 441, 71782921447341843258035555, 8031.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 442, 46049480431099946625058635, 3780.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 443, 73616344208382060859082940, 6684.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 444, 50333253171903932204461890, 8995.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 445, 89804487047732116098059506, 1659.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 446, 37496929178899503555650672, 2215.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 447, 62470375958970602615653137, 4440.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 448, 26683940946941736580479781, 1813.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 449, 69054521833408771244114160, 2383.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 450, 04765739749012748556063560, 1556.59);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 451, 63745662169581546439280069, 7458.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 452, 85959032161531873600636687, 3424.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 453, 85226693477235497957034541, 376.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 454, 19627419602072176554650792, 5369.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 455, 50786806299071105852230551, 4747.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 456, 10407994237414453060919611, 2946.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 457, 26702321629192202859338192, 8952.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 458, 09144462041620553781083707, 6341.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 459, 67502350753862953470715642, 1712.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 460, 08724127683769635735960346, 187.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 461, 46238456043184866053319088, 5547.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 462, 75239654771313918246569072, 487.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 463, 85686014420271651223415801, 530.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 464, 48493676567417541863586887, 2618.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 465, 34476406271025960963041213, 1474.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 466, 48333740239101649795472426, 7518.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 467, 84602229979919666665684143, 1582.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 468, 82191588035619459170669490, 1278.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 469, 96487445603524976156073557, 588.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 470, 40976263700823504637356275, 9514.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 471, 73481448188668740471419060, 6597.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 472, 79802277167266935898677142, 69.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 473, 47471102045253620703501976, 9655.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 474, 91766267758962694199612372, 2360.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 475, 40286622209450596431493051, 9012.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 476, 51637509630391175019881970, 6575.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 477, 37657914635372943922278576, 8723.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 478, 02752787313180221306901649, 5049.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 479, 66054234236756024629398260, 956.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 480, 51685835065597899708998662, 8587.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 481, 27518037329329081572333709, 3629.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 482, 27366590154739790194716890, 491.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 483, 91070358889257855000402824, 6378.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 484, 95004921985579521449356200, 1079.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 485, 10342168468210148678772147, 3607.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 486, 01822590706581331376274986, 6510.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 487, 14208125055279106216070210, 1422.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 488, 97941876045770856450314049, 2115.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 489, 35923270570661192813252548, 8878.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 490, 25023291618355273893438888, 6655.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 491, 97696110851588939797097357, 3095.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 492, 58653530976197082761471424, 446.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 493, 47822559865605024486573134, 3169.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 494, 39357793764857029754411220, 3967.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 495, 27223698760625483201973404, 3477.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 496, 71786466576993963363603237, 9719.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 497, 84532906413808817097546213, 8544.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 498, 11688248762328161116213136, 3484.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 499, 96495284144646945380276199, 1781.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 500, 64448539121001503652217590, 4380.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 501, 29513593695412853353594011, 4073.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 502, 04870906233534337935967839, 7077.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 503, 13279726108579854317324713, 9639.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 504, 05037604051640338706781932, 45.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 505, 60574777780512922369713343, 7276.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 506, 55998741294159490428795819, 3194.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 507, 00222499128207498543587908, 2090.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 508, 79672101545795873548181436, 3240.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 509, 64805947638933988101656595, 4487.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 510, 56955830916683000050840933, 6152.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 511, 44386220560871673518790687, 8397.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 512, 94432270684323718037825128, 5166.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 513, 98174815307610450064461368, 6761.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 514, 65784852507294078600136274, 5888.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 515, 81318322575015236066622778, 4111.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 516, 09362795488865544311405081, 2508.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 517, 09008524864053954863706992, 1314.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 518, 65710275983650697314698691, 8320.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 519, 77752503944181554031745876, 2511.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 520, 01615800605756484957603748, 1201.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 521, 96483297234582210695505777, 9121.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 522, 89700080133295110319175913, 4023.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 523, 56878358206164032405805897, 4971.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 524, 76764946318876728189887046, 7246.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 525, 94546381445698371428281771, 7428.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 526, 43049876768853394066226813, 1365.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 527, 33005846728471555053165845, 708.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 528, 20252910838288656207802564, 464.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 529, 94501337556368379309407769, 3514.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 530, 36646730939986705948614881, 7943.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 531, 27342254492270261581322723, 536.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 532, 10213299089864085960900935, 5943.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 533, 25957689661678798649890235, 9971.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 534, 06500132770531756386818402, 958.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 535, 50383607149865228119670299, 454.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 536, 44282595635625102076048843, 6545.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 537, 40849778137077903412881666, 2301.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 538, 20810767535963942634162994, 344.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 539, 55492453503429287529747559, 2636.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 540, 94963697892538479179522563, 6670.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 541, 17548766657543302443370774, 4824.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 542, 25467076953422628037663197, 4052.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 543, 09682335029209997762359794, 3483.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 544, 47155129582037213909525004, 9229.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 545, 31592399081554763361448792, 2114.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 546, 63924611755999909880601540, 1810.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 547, 86161450475969305676283964, 7376.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 548, 32371806976647822906507384, 7085.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 549, 32186038433214819640482276, 6603.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 550, 72544289898301270736688640, 9327.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 551, 48830099908417447007364479, 7500.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 552, 49073462479824338077006053, 652.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 553, 67842539823733376035445707, 8321.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 554, 03978857848244030182791257, 9740.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 555, 55988014245620904178625688, 6828.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 556, 87716543297416412594044104, 1034.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 557, 25010430713291119057203471, 1428.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 558, 61595959511310441498238681, 6743.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 559, 47440386683262747795325462, 8945.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 560, 78595006104580290125723166, 9766.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 561, 75384529800343502391926965, 2258.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 562, 62517094062367400119855951, 4959.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 563, 99751368011817962368743780, 4568.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 564, 58066782419826539861974887, 6415.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 565, 10086330037903693490793779, 1386.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 566, 44826493048064316182471508, 6916.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 567, 00935759948328532887151445, 1297.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 568, 42870922389659459978074171, 1715.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 569, 64164199524076475830275019, 5068.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 570, 24534863175557366723763518, 643.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 571, 68743044653810594499049622, 5676.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 572, 46360890108073947441699207, 1778.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 573, 30549197878423900204874731, 2838.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 574, 93292921490449651125049805, 5581.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 575, 23129287249293626774963992, 5702.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 576, 27480904560425115277398964, 8458.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 577, 80533316405927396390726728, 2792.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 578, 33162533956028868155089128, 9552.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 579, 59321779164124346914850856, 8431.13);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 580, 06773633603542227150776655, 795.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 581, 21405470952491937475153163, 881.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 582, 91838188047675769478442531, 827.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 583, 01475431033505334796217265, 3110.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 584, 63750631382289980114136340, 9844.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 585, 75394756482364678654839004, 6814.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 586, 65819936722804793383534604, 7870.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 587, 78911074298666071886454280, 8154.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 588, 66513761618052786036260965, 3956.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 589, 95118004513655223456972616, 3808.3);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 590, 71805638475140257059269322, 8631.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 591, 92676615135502430780759602, 3210.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 592, 88110187406175708262881075, 841.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 593, 99511570999012319612290292, 3414.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 594, 60576713104871722708402406, 5828.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 595, 95266874751655454141049378, 6133.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 596, 83615267431025235718720090, 707.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 597, 54664246130565626980763658, 6958.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 598, 81257598713288873139211873, 4550.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 599, 33522602581406397885274009, 8890.80);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 600, 27479097934257061148288659, 6001.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 601, 28173250518322822587625892, 1448.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 602, 57895846030445849715585819, 9852.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 603, 57291148304116887684147073, 5160.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 604, 57296353253468154739656833, 9010.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 605, 44448296062625968508913722, 7170.3);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 606, 18308511833478335151457602, 2035.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 607, 09966382749609908504234854, 7310.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 608, 58768822800597299099672622, 532.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 609, 74070775199362348693164314, 7435.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 610, 94180496132943073112178616, 3180.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 611, 92930281843825233249331479, 3995.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 612, 11988078835327391736953994, 3015.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 613, 38768169763297072233868202, 1715.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 614, 82065867333127906474699186, 9653.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 615, 58636726297167817400293712, 4366.37);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 616, 40979719017707164548130394, 1993.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 617, 85329282655537286451417080, 472.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 618, 26511443308239041712983879, 6941.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 619, 14486558701523062909514419, 5669.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 620, 77349764189064633563043613, 9227.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 621, 36712006065997689613556580, 4906.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 622, 23967973906199965461130449, 1091.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 623, 18167154231014981928031621, 7457.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 624, 58617403035751762370509291, 3066.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 625, 92253012467469988178518034, 7320.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 626, 00409676618002027633815532, 1846.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 627, 97757593618253301204088908, 1952.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 628, 28190216217017459263772940, 3733.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 629, 63931346597414785509650313, 9791.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 630, 75881293720915524637210110, 9622.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 631, 41574955748901068311793214, 2720.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 632, 70477161220299688228836405, 1549.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 633, 29746300402393892169885412, 4544.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 634, 76828450666836828578426479, 4801.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 635, 19114637474441785155481548, 578.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 636, 23086194768203845887383237, 3279.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 637, 93516811453404367944023243, 5386.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 638, 70505222976199848025251125, 1942.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 639, 77679322497932555215882272, 5027.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 640, 54710246640907491924185194, 363.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 641, 60055772359557389999214589, 9147.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 642, 58302787950996731069916948, 3988.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 643, 97478075038686261985419967, 6324.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 644, 20440214330090318688142445, 6959.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 645, 09807561307251448473859041, 7747.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 646, 26033986376097682530356713, 1563.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 647, 83489267168891701187904305, 7986.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 648, 35608026170926738037918476, 2011.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 649, 09071893313311088834840825, 5168.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 650, 67856946542058514697424088, 1017.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 651, 51487336234226331417865353, 1629.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 652, 14374552121759713427433282, 6222.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 653, 01851448819341590595288214, 593.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 654, 77731254602987559077739588, 2652.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 655, 89853383657118230954071037, 6709.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 656, 80697366691126055628949982, 2423.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 657, 18386708327939280653690701, 2614.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 658, 61409627634913695703280237, 7078.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 659, 16640289332421211426594772, 4279.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 660, 11531682575823237652663601, 3172.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 661, 25171688630022469209104316, 2989.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 662, 06079203323115667106340745, 8963.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 663, 29817604525359037437277535, 5043.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 664, 27434615627472005176619738, 1573.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 665, 55716020618081635452321338, 230.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 666, 47565443038185799130215255, 4019.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 667, 26645577613901717494680879, 6952.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 668, 80390447285872510830536440, 2265.31);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 669, 48049230681634324218150594, 8895.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 670, 17387208335588726226643844, 2134.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 671, 42492205332926113225469149, 8341.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 672, 21994090242375298328844863, 5630.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 673, 06921239825853820012005796, 1032.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 674, 31545158376729485803401430, 506.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 675, 34781985458395931970339771, 2137.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 676, 05193590796417616451098182, 4773.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 677, 70795259978079910935194489, 2079.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 678, 79013336648598822174283947, 3390.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 679, 76501758124431458249941226, 691.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 680, 10043722460095656123394346, 7578.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 681, 11970661830983055853348235, 4004.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 682, 26228211570447468614248144, 1393.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 683, 14171752974141523904945608, 5522.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 684, 73321847672981188070464955, 8159.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 685, 18508985129584118685004760, 9509.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 686, 13519571275828667641273254, 147.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 687, 08550806774527825812459808, 4917.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 688, 90658618262268615794066307, 8289.15);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 689, 79049682491426319804113568, 6865.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 690, 12370085325314529248277771, 50.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 691, 28239175118840770560777411, 9835.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 692, 33014833187235627255236127, 9472.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 693, 36643127972155121508869808, 2424.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 694, 11519374559275507040597383, 1101.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 695, 85217950142366305755778852, 2579.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 696, 15200629187081140061471860, 987.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 697, 84874752567422397014966742, 1609.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 698, 25453599260924578692270643, 1571.59);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 699, 88394728577910333741545388, 8236.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 700, 49959620185796484569443923, 880.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 701, 25035085582305963383661869, 8034.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 702, 43382779877573155150189518, 8371.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 703, 95525169750070124787603386, 9508.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 704, 03907891425387651835679796, 4015.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 705, 10776232423149427861591189, 8962.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 706, 45940846315374127329401696, 2333.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 707, 41865964062592971736443849, 924.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 708, 05275358719346179105921599, 6903.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 709, 69883655210297862863825218, 7817.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 710, 96799696357414732954547617, 6430.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 711, 51217990613181386720294108, 7506.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 712, 22950919566630610888208655, 3606.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 713, 39858408796407616870471398, 85.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 714, 25393751658705129295261890, 9367.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 715, 53326590408742148573418322, 6836.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 716, 10524317097412583079230624, 9949.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 717, 26445919566375241763171901, 9222.4);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 718, 89305298633262593268070171, 2102.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 719, 57074967268243978739805870, 4339.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 720, 43020179162171106285829438, 1112.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 721, 21784617720158470527366833, 1482.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 722, 15556813726038379124482034, 4827.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 723, 11764167606068152324895909, 876.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 724, 20410151763244802009771308, 7545.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 725, 52601807434195153252289274, 1200.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 726, 04482202785633200051609558, 99.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 727, 04530491905336147115403197, 7584.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 728, 36193326108726596238216789, 1933.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 729, 52982264895900952741469968, 7320.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 730, 12945576521202885868838374, 5983.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 731, 70366306174993362946768557, 6684.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 732, 26380877804608053318704674, 9572.25);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 733, 59376548248933926817578971, 8673.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 734, 74032778733107373349438932, 253.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 735, 40584061858902026903386857, 8017.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 736, 96410540992253430014293865, 3197.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 737, 56265794365603581720336597, 6041.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 738, 41383259361195162769914140, 2460.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 739, 66016070316684841593765224, 7708.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 740, 20206891105786847706224724, 8262.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 741, 54159146126611107347584732, 831.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 742, 63556562204754911732143085, 1979.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 743, 61717204033955026258284881, 2381.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 744, 16751158902978251246867202, 543.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 745, 00434382928939419039195390, 2051.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 746, 60282795840418623826411536, 9002.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 747, 65859656984825746138114153, 2291.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 748, 27916658324144596864091714, 9271.3);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 749, 83014164237286863512732489, 8371.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 750, 87133593062421281639750835, 2583.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 751, 37111220980393327215781093, 7229.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 752, 94551779099215300594046216, 5805.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 753, 30002057392934427201781273, 9567.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 754, 19881999293819108241853446, 5473.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 755, 01730386215309353969093059, 4123.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 756, 17890487915694035265695872, 2303.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 757, 45516923232884472249502946, 2421.30);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 758, 14902564933944316437086276, 7255.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 759, 78243675186191055827356344, 9546.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 760, 06643985415082303851084387, 397.40);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 761, 99880676513581426127062556, 7701.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 762, 56335090385948623731598944, 4088.46);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 763, 10981315254766025604846280, 1786.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 764, 50715616387750544442455552, 485.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 765, 20844537503533761228088671, 3917.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 766, 22021003475607766292777238, 3540.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 767, 36453853186221757322930252, 586.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 768, 14443513301825486145040332, 8088.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 769, 43938316382458100684065956, 8141.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 770, 89129943332583105814756988, 489.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 771, 33852289028696183494391758, 3673.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 772, 81241395456432294488451139, 9299.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 773, 63440394068633791435919020, 9763.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 774, 63470899009612695872703131, 8566.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 775, 25124252764080216565799421, 341.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 776, 46090363544399620363792365, 3301.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 777, 81926181486663956856560911, 3006.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 778, 84363559462976740908337985, 1594.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 779, 73154870392005867556701157, 6911.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 780, 42665916922649090020433199, 1039.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 781, 32965976070678196919255466, 62.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 782, 57767872666091277140739110, 2884.39);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 783, 22686095544613618220235072, 7541.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 784, 79580750933646258241436129, 2814.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 785, 23455466775416467908133726, 1458.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 786, 13401808851969354546280815, 516.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 787, 88232597181857764182227521, 1830.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 788, 00492583431277176229371200, 4194.93);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 789, 29532087119608543151700175, 7495.22);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 790, 11916336470900098808764541, 6632.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 791, 79754072767391618247826242, 2416.90);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 792, 31590708572369937662871885, 5753.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 793, 50132671535349879218923642, 8623.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 794, 39879815326628591407726092, 7183.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 795, 65530877216040196082684675, 3028.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 796, 41801791662906327804494919, 6836.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 797, 35973132619141109558395661, 2406.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 798, 25715229811659662193396413, 2296.39);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 799, 40681580003461217785221367, 6704.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 800, 81045024495335474747744261, 6367.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 801, 40248896499884247302318755, 8366.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 802, 44189125583069974693049254, 2178.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 803, 22201514328644491841702246, 6610.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 804, 08016635484272102623917790, 2156.21);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 805, 32535601219829828755590700, 2179.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 806, 23474466585151079216333443, 3021.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 807, 39867307360409423491134526, 5339.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 808, 47414841716046301911945859, 9560.38);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 809, 92711232355435821027788183, 6054.46);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 810, 66319927692580311256395441, 8439.52);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 811, 43482718398085046315700944, 4648.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 812, 77371415633243105879116076, 5699.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 813, 05073615915436174340453334, 166.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 814, 77641979619150947432145360, 4303.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 815, 42111473609806905865519075, 7530.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 816, 38837327108284612515364947, 7052.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 817, 40275108353273470116341940, 5793.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 818, 47318325788580235001819665, 1252.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 819, 04992922984747911847218648, 718.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 820, 82336330013877619785599990, 898.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 821, 32825384984319658558183584, 3990.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 822, 93536085143711696560762207, 6757.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 823, 11128897580398575571933570, 3988.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 824, 84202166414234456127447797, 8451.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 825, 71020606834120389613288616, 3189.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 826, 91507509150267513928583126, 3794.17);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 827, 25345366302255070194840100, 7132.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 828, 97287712320882281466781936, 3535.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 829, 50741176178656183338669265, 4477.71);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 830, 45196132135459275843958904, 585.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 831, 50357912204348288684953521, 8627.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 832, 26452201843349262496087735, 8484.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 833, 93494153458698906570086358, 2588.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 834, 72321127178989258184447862, 4361.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 835, 18967759811641069081553596, 473.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 836, 18554441565105509175042781, 7282.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 837, 27266682831832312948313939, 6721.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 838, 45390865940094461730111536, 6641.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 839, 63332128013798031550403052, 2397.9);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 840, 56324174795929352564612997, 4232.12);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 841, 88861097299419100458159652, 7068.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 842, 46604647340524740774194157, 833.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 843, 94236719181091907389993468, 7758.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 844, 18873385890301005907026497, 5397.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 845, 37197857754006804882703577, 1787.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 846, 10551413172994371773935330, 902.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 847, 53889007793495476892555631, 9451.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 848, 73941734589093863054592038, 3431.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 849, 46845895752553431810977002, 8445.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 850, 02519038115382237931260220, 4513.10);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 851, 83412398020015187450368874, 3043.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 852, 11378998231372554033094193, 4559.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 853, 10243537995394481433913335, 7779.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 854, 99749415606152693493126232, 1696.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 855, 94093034543946194151148232, 8213.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 856, 29169020611511424796588658, 3401.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 857, 93094223055436940906320232, 41.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 858, 00298178403900291348945067, 754.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 859, 94731206295891203579084853, 9120.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 860, 10795621083319261265132389, 5495.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 861, 04822856074402113670961623, 6000.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 862, 82078538575069615672728509, 6935.98);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 863, 69991319769545586252636087, 3075.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 864, 49579571073773413635142007, 6582.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 865, 29502262143212250071487398, 6679.66);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 866, 69925908324461188586112130, 8332.3);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 867, 14638225578112974050770395, 4749.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 868, 03409716885934261148560068, 9590.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 869, 50516951040463497117499313, 6491.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 870, 76655675618911288355586921, 722.95);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 871, 11846031277373814570263969, 5468.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 872, 85388834596687329314213993, 7765.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 873, 16000193406009195805793866, 9150.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 874, 44772737016301358384904231, 5607.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 875, 87784154618167097586091779, 2961.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 876, 11127658789133073858995711, 3348.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 877, 98109114443363486990141237, 797.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 878, 31811557243133083088061546, 3979.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 879, 54358963856060406912031714, 7258.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 880, 13264306772593265597885456, 5168.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 881, 21305712922758646378678648, 9751.0);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 882, 57086924202301396048679806, 8827.26);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 883, 37612772747954300969767040, 5525.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 884, 16650780627680581798076659, 5624.63);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 885, 23351328523407928474266669, 7500.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 886, 93625292784623861335345698, 2744.50);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 887, 82445628502750106839181287, 4579.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 888, 75049882781359091909656656, 1053.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 889, 70898686496285864142324408, 9514.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 890, 46823168011183675287827205, 6592.28);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 891, 73914611983886516028968540, 2946.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 892, 78342866590474029560648729, 396.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 893, 23568702399485788811627669, 80.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 894, 72697045279331666388208650, 8178.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 895, 92607597257328659767050249, 2304.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 896, 85460965061787082708993151, 8341.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 897, 97149699798425083374795616, 974.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 898, 77999224323191866518538190, 2621.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 899, 28330638345783393156520629, 1693.78);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 900, 13187908780283046356392915, 6758.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 901, 83626771736030297722449162, 4595.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 902, 98121980632005524358045246, 6560.19);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 903, 95414617544884297595971971, 9577.81);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 904, 39814803395084171077182698, 5071.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 905, 96146930403041972676762749, 5405.64);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 906, 08055637714405525272062408, 8523.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 907, 18183771389591946168582293, 5281.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 908, 98456944593526657774865518, 1695.53);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 909, 99841880082568779602012036, 3067.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 910, 04163499323141371183026503, 2060.87);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 911, 69284153415184312665547242, 3205.11);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 912, 35220163476840356036052189, 1637.77);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 913, 89236741797507988873769937, 5581.35);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 914, 42004757082277001138625407, 5490.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 915, 38714106642480768675607290, 421.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 916, 69252046169550366267094856, 9007.88);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 917, 07929792019027870376050012, 722.67);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 918, 52351403842429022564679689, 1196.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 919, 95620639547548928217545284, 5342.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 920, 62362902518198821352923331, 6317.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 921, 42400745632779507819200541, 7479.16);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 922, 79068583518293328777033309, 2602.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 923, 44152055320564265215101351, 864.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 924, 33095531421883426709080719, 5918.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 925, 04000460749067353799704097, 5358.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 926, 09187207576327166948139887, 74.6);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 927, 71029678132990910610715570, 5802.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 928, 32966817311697835306199221, 4209.94);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 929, 33281585041568514453106956, 4115.7);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 930, 75306409185051817398405029, 4059.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 931, 08781162521057840661044479, 795.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 932, 49958178934443518132554489, 9236.42);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 933, 58176606464441575465823548, 9672.69);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 934, 42795377130979922379178203, 8220.75);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 935, 85636185368843414563779057, 8674.27);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 936, 35854071527177499055963309, 3830.32);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 937, 82705862434899193086404645, 4473.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 938, 80651168709794597321082449, 3644.60);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 939, 88811618820204972307480206, 1438.29);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 940, 47788425043958880520960346, 8120.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 941, 96985511394503185133470106, 8935.1);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 942, 87803173354818269149502135, 1978.54);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 943, 49505909356839746162807955, 9550.47);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 944, 15742749989760912372621385, 6055.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 945, 28592987549510453805636375, 1809.58);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 946, 58565914910284578629675259, 8566.73);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 947, 38790647267719341923004071, 7217.56);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 948, 09299095277264977198464888, 5155.83);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 949, 90092503209192596657756925, 8853.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 950, 68831596038330263709882304, 1118.23);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 951, 09089803544621084545106449, 9990.36);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 952, 38878302600303582255073481, 4107.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 953, 35686639917798653613488222, 9810.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 954, 71016801410481363082698141, 2849.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 955, 00810887688611983166294880, 2364.84);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 956, 41278106397483322445534835, 9741.96);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 957, 27230294513989944438428576, 2168.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 958, 31210350275709432402298977, 9455.33);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 959, 55912668775469125545523035, 289.45);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 960, 14718455520687647847968313, 9097.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 961, 85667395102859781805835459, 9205.48);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 962, 01351713085861336603861880, 1173.79);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 963, 92309422373633069565764349, 8774.24);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 964, 15932760045835509028569831, 9166.85);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 965, 87029009346030547116471156, 4825.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 966, 24649594199607672296029302, 4228.8);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 967, 68826369039348686358804035, 7785.14);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 968, 05544688867776109050867006, 1723.61);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 969, 44977695318339396498951323, 9458.20);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 970, 70554877028092358660427622, 5034.92);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 971, 98213851339611846776071400, 8152.13);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 972, 82863060027625364568682398, 3070.70);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 973, 40284727246735396896562631, 4272.49);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 974, 52625319754240279989725928, 5030.86);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 975, 98325770668132912577297009, 244.76);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 976, 17188080623933080631891016, 3335.65);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 977, 98944914724406122368324040, 1537.55);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 978, 52647381152714340172829286, 2119.91);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 979, 99294125597703159971335823, 5402.43);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 980, 35436871735195966789995471, 8980.74);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 981, 38454314114992798341692548, 2229.62);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 982, 76948304475350744162176695, 3805.5);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 983, 04142412183527247745308328, 5243.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 984, 77585301667182140086398161, 7637.44);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 985, 07004159964650024520908523, 6842.89);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 986, 88552809713291216054450768, 1398.72);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 987, 33386977083999397189227895, 6932.97);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 988, 18528451080033500067732140, 6777.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 989, 57309954385719313185183409, 6383.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 990, 30164792056591150649765355, 7617.13);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 991, 99135315674458507371973728, 8021.18);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 992, 63914923293551031800000641, 687.34);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 993, 09089041617919811506678556, 9348.41);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 994, 78726501347886621836394759, 8029.2);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 995, 44776944461341514510081568, 7886.51);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 996, 50167673994695139271867859, 4229.57);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 997, 52730514393822168455137296, 392.68);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 998, 97078124263998873437178404, 1417.99);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 999, 21924434017509183560042832, 3628.82);
INSERT INTO konta (id_klienta, numer_konta, saldo) values( 1000, 47336165911618287080489072, 3660.48);



	INSERT INTO transakcje (id_konta, kwota, data_transakcji, typ) VALUES
	(791, 186.69, '2023-06-05 18:03:50', 'wpłata'),
	(665, 3464.63, '2025-01-29 18:03:50', 'wpłata'),
	(849, 3459.5, '2024-11-17 18:03:50', 'wypłata'),
	(749, 1072.37, '2023-08-06 18:03:50', 'wypłata'),
	(342, 3825.43, '2024-07-21 18:03:50', 'wpłata');
	
	
	SET FOREIGN_KEY_CHECKS = 0;
	
	TRUNCATE TABLE Przelewy;
	
	TRUNCATE TABLE transakcje;
	
	SET FOREIGN_KEY_CHECKS = 1;


INSERT INTO karty (id_konta, numer_karty, data_waznosci, cvv) VALUES
(11, '1423019896438920', '2027-04-05', '429'),
(11, '4597205231412024', '2027-12-31', '088'),
(11, '0713658512900475', '2029-01-22', '406'),
(12, '5194812307296935', '2028-03-13', '906'),
(12, '9837178595876841', '2029-01-25', '131'),
(13, '7692674238699892', '2028-06-01', '036'),
(13, '0084278020165578', '2030-01-30', '743'),
(14, '2093484415300125', '2028-07-20', '745'),
(14, '9893370703950943', '2028-10-06', '981'),
(15, '3116134540164944', '2027-02-24', '197'),
(15, '8647685337251277', '2028-02-13', '331'),
(15, '9867996664628053', '2029-01-24', '578'),
(16, '3640738094493455', '2029-04-05', '251'),
(16, '5526414006313572', '2027-06-21', '053'),
(17, '7642094703416712', '2028-08-25', '032'),
(17, '7072001637196236', '2027-05-29', '970'),
(17, '1387807866313546', '2028-04-22', '600'),
(18, '9385882476629262', '2029-12-11', '546'),
(18, '7208082742350558', '2028-12-24', '805'),
(18, '7087327353801545', '2028-11-20', '031'),
(19, '1336852968549357', '2029-01-17', '980'),
(19, '8881553888086084', '2029-08-10', '430'),
(19, '3466725748525104', '2029-07-21', '571'),
(20, '3887078416441666', '2029-10-25', '257'),
(20, '7645319709790803', '2028-09-19', '512'),
(21, '9378783906496662', '2029-08-30', '517'),
(21, '0749210601996920', '2029-01-11', '107'),
(21, '5056527676708903', '2029-09-02', '847'),
(22, '9296766955227345', '2029-03-02', '502'),
(22, '4944222749693701', '2027-09-10', '981'),
(22, '0165086661887096', '2028-03-08', '909'),
(23, '2112005641545230', '2028-12-03', '066'),
(23, '2743963428981972', '2028-07-03', '390'),
(24, '7265939574014202', '2029-09-26', '452'),
(24, '4982242002627825', '2027-05-10', '994'),
(24, '7904779295306501', '2027-12-19', '386'),
(25, '4529930046798031', '2029-06-27', '118'),
(26, '2015992000884854', '2029-01-28', '035'),
(26, '7336883740021832', '2028-05-13', '446'),
(26, '3583125287511336', '2029-11-20', '992'),
(27, '1451516476360978', '2029-04-07', '736'),
(28, '7557064236921707', '2027-05-11', '281'),
(28, '2012478494094411', '2027-12-03', '778'),
(28, '7154123188292701', '2027-04-17', '111'),
(29, '5097125450268491', '2027-11-23', '047'),
(30, '6047055712011765', '2028-04-28', '447'),
(31, '6392599447883316', '2028-07-29', '103'),
(32, '6849344422576557', '2027-11-03', '224'),
(32, '2236392666042123', '2027-05-22', '156'),
(33, '5767037312707584', '2027-08-14', '765'),
(33, '9287702592836618', '2029-10-04', '063'),
(33, '5317637714658269', '2027-03-04', '988'),
(34, '9767185544352399', '2029-08-01', '529'),
(34, '1941351215916814', '2030-01-21', '396'),
(34, '4797177994920086', '2028-02-28', '729'),
(35, '3391243643711173', '2027-03-21', '647'),
(36, '8422595983048799', '2029-09-14', '819'),
(37, '8175788876931989', '2029-05-31', '500'),
(38, '5992453288967828', '2028-01-16', '119'),
(38, '0119225460253926', '2029-08-07', '544'),
(39, '6133662110601847', '2030-01-10', '203'),
(39, '8857858044471934', '2029-06-14', '995'),
(39, '9246768928698570', '2028-12-26', '171'),
(40, '0022468542774731', '2029-05-19', '136'),
(41, '3210591586200157', '2028-07-19', '687'),
(42, '3949957955613333', '2028-06-23', '384'),
(42, '2784706550371666', '2030-02-10', '336'),
(43, '2084467298401362', '2028-10-23', '040'),
(44, '5704497002344830', '2028-05-10', '205'),
(45, '3792697514478475', '2028-12-02', '596'),
(46, '8512965126669027', '2027-10-09', '443'),
(46, '5414503553770497', '2028-06-25', '614'),
(46, '0460015937488622', '2027-11-02', '600'),
(47, '7057221675282190', '2028-04-28', '805'),
(47, '7163720237384140', '2029-01-23', '145'),
(47, '3756476119493544', '2027-03-18', '593'),
(48, '3723871429052923', '2028-12-25', '978'),
(48, '3643506937323577', '2028-08-04', '392'),
(48, '9102218125472538', '2029-10-12', '816'),
(49, '6392319276266219', '2028-10-01', '335'),
(49, '4828005270379903', '2029-05-27', '703'),
(49, '8960381084476930', '2029-02-11', '128'),
(50, '5617174792356723', '2027-12-22', '523'),
(51, '2189291617957255', '2028-10-07', '928'),
(52, '6388335849576959', '2029-12-03', '233'),
(53, '5743758555905216', '2029-05-07', '226'),
(53, '8401530141199342', '2029-03-18', '052'),
(54, '1131588582993557', '2029-04-26', '500'),
(55, '1456459830297286', '2028-10-27', '269'),
(55, '3382163036195541', '2030-02-11', '554'),
(56, '8286494440113523', '2029-11-14', '627'),
(57, '8138227526949111', '2028-02-06', '400'),
(57, '1758824490795147', '2028-06-26', '838'),
(57, '4625254224892560', '2030-02-18', '615'),
(58, '7298899337520292', '2027-06-14', '950'),
(58, '0720267309154112', '2028-04-04', '591'),
(59, '2089986234294791', '2028-10-10', '814'),
(60, '1486958963512728', '2028-04-08', '047'),
(61, '8153975262790582', '2029-12-10', '486'),
(61, '8793525966895458', '2028-01-19', '078'),
(61, '9612249646356321', '2028-10-26', '479'),
(62, '5799724291538671', '2028-06-22', '316'),
(63, '0028825262154874', '2027-03-27', '654'),
(64, '2903122691861403', '2029-09-03', '382'),
(64, '0577472415772262', '2029-11-15', '898'),
(64, '4495842651378563', '2028-05-06', '176'),
(65, '3084265221723722', '2028-06-20', '630'),
(65, '1365117080873511', '2028-09-07', '429'),
(65, '8264454049023576', '2027-07-06', '126'),
(66, '7681031428332132', '2027-04-16', '321'),
(67, '7923556163405145', '2029-09-01', '225'),
(67, '6492119118455937', '2029-08-25', '619'),
(68, '4992755213321491', '2027-04-13', '155'),
(69, '1616040837555038', '2028-01-21', '464'),
(69, '3289366259848910', '2027-02-25', '088'),
(69, '5965282693916507', '2028-04-22', '463'),
(70, '3343648178434629', '2028-10-12', '908'),
(71, '6770858020792356', '2028-05-06', '513'),
(71, '4632748447062834', '2029-01-15', '613'),
(72, '5537633351304792', '2028-06-01', '005'),
(72, '8526357728702300', '2030-01-22', '267'),
(72, '9624824229866940', '2027-08-27', '234'),
(73, '2107775773016160', '2028-12-24', '608'),
(73, '3268655519819808', '2027-11-13', '159'),
(74, '5706014762255875', '2028-07-21', '320'),
(74, '9651406328203368', '2028-01-21', '895'),
(75, '2820615461208535', '2029-09-23', '551'),
(75, '6413617024181187', '2030-01-14', '645'),
(76, '3668876154786211', '2030-01-12', '687'),
(77, '8911961804179114', '2028-01-18', '749'),
(77, '4063011216013840', '2029-06-17', '979'),
(78, '9420784357683520', '2028-03-07', '945'),
(79, '2842007594323623', '2030-01-09', '240'),
(79, '8477292317967627', '2029-08-23', '958'),
(80, '3719440325566352', '2028-07-31', '612'),
(80, '1579540559876406', '2028-08-11', '122'),
(81, '1051722314571415', '2028-12-13', '275'),
(81, '9728872440455017', '2030-01-11', '538'),
(81, '2312948329545389', '2029-12-14', '557'),
(82, '5715588474860097', '2029-11-09', '547'),
(82, '4339034675621544', '2029-04-07', '522'),
(83, '6290935160552934', '2028-03-21', '151'),
(84, '4939916647179830', '2027-10-12', '143'),
(84, '7766339102709138', '2027-10-23', '163'),
(85, '5225387794423035', '2027-05-17', '590'),
(85, '3117538590057217', '2030-01-27', '836'),
(86, '3725603498535567', '2027-03-31', '175'),
(86, '1806415911082009', '2029-11-02', '776'),
(86, '9712977462383568', '2029-06-27', '838'),
(87, '3972269095701766', '2029-09-18', '077'),
(87, '9487679653558799', '2028-04-18', '396'),
(87, '6116785601384846', '2027-07-15', '273'),
(88, '9732658475325417', '2029-12-12', '552'),
(88, '0167565136046016', '2028-02-24', '250'),
(88, '8705481302913887', '2028-06-02', '049'),
(89, '7361357022422739', '2027-03-19', '739'),
(89, '5839188475603358', '2027-08-30', '954'),
(90, '9656915997568255', '2027-03-08', '683'),
(91, '8052751996256503', '2027-06-07', '185'),
(91, '0677907532728414', '2027-11-13', '307'),
(91, '5970654829482019', '2027-11-04', '936'),
(92, '4915967604874247', '2027-03-08', '493'),
(92, '8285674358515368', '2028-07-09', '843'),
(93, '4336261386965798', '2028-02-13', '383'),
(93, '1274413210669571', '2029-06-05', '081'),
(93, '3919160437635777', '2028-03-14', '689'),
(94, '8122273740653457', '2029-10-04', '031'),
(94, '0585248954707535', '2027-04-21', '775'),
(94, '2995675123170310', '2029-05-25', '877'),
(95, '3927018476767348', '2027-10-26', '844'),
(96, '7876751541841716', '2029-03-30', '302'),
(96, '4247067382134542', '2029-05-26', '560'),
(97, '2481792658480189', '2029-06-30', '703'),
(97, '2389307488604530', '2029-03-30', '919'),
(97, '6818970931501720', '2030-02-02', '077'),
(98, '8372648370507125', '2029-09-25', '149'),
(98, '1234361382562460', '2029-09-06', '871'),
(98, '3440114090642114', '2027-10-02', '150'),
(99, '6139418411778046', '2029-01-24', '380'),
(99, '2842722633457743', '2028-01-22', '880'),
(99, '3404254753497129', '2029-10-11', '728'),
(100, '5307684086420588', '2028-03-06', '916'),
(101, '0573482286293600', '2027-08-11', '594'),
(102, '6403628064424713', '2027-10-27', '703'),
(103, '3118724702117046', '2027-11-06', '432'),
(103, '1747794589780277', '2029-02-11', '127'),
(104, '8351496160657319', '2029-08-07', '164'),
(104, '3401909298590975', '2027-12-18', '520'),
(105, '3399873446726311', '2029-08-24', '565'),
(106, '6881837991980854', '2028-07-23', '729'),
(106, '7874901727619039', '2028-06-08', '139'),
(107, '0167274921483685', '2027-03-30', '324'),
(107, '7481562230901122', '2027-05-25', '997'),
(108, '5809220605198262', '2030-01-26', '438'),
(108, '1306379270964945', '2027-12-30', '032'),
(109, '9976428095572493', '2027-11-26', '922'),
(109, '7534088738694531', '2027-09-16', '174'),
(110, '9918146845663275', '2029-01-13', '334'),
(110, '0094852558487926', '2027-12-01', '601'),
(110, '7522162449207053', '2029-03-21', '332'),
(111, '9888358903781930', '2028-10-24', '405'),
(111, '4497994477583642', '2027-09-15', '966'),
(112, '6508923356771143', '2027-03-17', '895'),
(113, '8313989931835243', '2030-01-24', '153'),
(114, '4348406256719525', '2029-03-22', '460'),
(115, '3282054000649978', '2028-06-14', '009'),
(115, '1315229250514199', '2028-10-06', '251'),
(116, '3016838909919486', '2027-03-14', '584'),
(116, '6366838443459641', '2029-01-23', '331'),
(117, '8097157217043581', '2027-06-17', '267'),
(117, '5290414578430970', '2029-05-26', '880'),
(118, '6105910678845954', '2029-06-06', '729'),
(119, '5165481222897318', '2027-12-03', '214'),
(120, '4549095133301151', '2028-12-28', '000'),
(121, '2815355862214434', '2028-11-15', '368'),
(122, '6926826878961636', '2029-06-22', '003'),
(122, '3466422340895640', '2027-05-09', '848'),
(123, '8617466955681763', '2028-04-10', '483'),
(123, '6571341724147124', '2027-12-24', '103'),
(124, '8139552896648134', '2027-09-05', '276'),
(124, '2298859064254061', '2027-03-21', '959'),
(125, '5427624326534772', '2027-05-25', '978'),
(125, '1684063720975416', '2027-03-13', '329'),
(126, '8761377346530704', '2029-09-05', '497'),
(126, '4564899496884084', '2027-11-13', '324'),
(127, '4111233926046133', '2029-01-06', '473'),
(127, '0800944549613506', '2030-01-29', '264'),
(128, '2219312531811066', '2028-12-11', '343'),
(128, '4033273574845628', '2028-08-30', '181'),
(129, '8774856771499718', '2027-05-20', '847'),
(130, '8417379833188127', '2028-11-26', '064'),
(130, '6375457940347179', '2028-09-26', '221'),
(130, '6799511019228161', '2028-12-07', '036'),
(131, '8087360791527786', '2029-07-30', '310'),
(131, '9888039900565842', '2027-07-22', '694'),
(131, '8889576282306227', '2029-04-19', '975'),
(132, '0612187926503472', '2029-02-24', '710'),
(132, '1396181378324922', '2027-10-08', '662'),
(133, '7287183420903369', '2028-08-28', '468'),
(134, '0238515507339969', '2029-03-05', '368'),
(134, '0880349869708676', '2027-08-05', '931'),
(135, '5821531514857199', '2027-10-13', '569'),
(135, '4077954116006501', '2028-05-31', '213'),
(136, '0455231912344160', '2027-08-08', '518'),
(136, '1603577557306144', '2028-11-11', '477'),
(136, '6446332494281515', '2029-03-01', '268'),
(137, '3695413924619329', '2028-06-15', '374'),
(137, '8383844280677114', '2028-03-19', '984'),
(138, '7374303496689595', '2029-08-14', '473'),
(139, '5038789499352696', '2029-04-10', '031'),
(139, '0264263007197222', '2027-05-17', '873'),
(140, '6398631130370151', '2027-07-29', '277'),
(140, '2141617676281742', '2027-03-26', '951'),
(140, '8085800396824678', '2030-02-16', '987'),
(141, '4545499220656813', '2029-04-30', '262'),
(142, '3941814283690292', '2027-10-14', '786'),
(142, '2076797715028806', '2030-02-12', '248'),
(143, '0397552211663554', '2028-04-06', '906'),
(143, '9979090892521978', '2029-08-02', '602'),
(144, '4593096814060632', '2029-11-09', '655'),
(144, '5446429725464227', '2027-12-22', '446'),
(144, '2285297425678863', '2029-11-07', '857'),
(145, '4699808134485781', '2027-05-08', '016'),
(145, '9567516729739392', '2028-12-27', '212'),
(145, '6700613318763333', '2027-05-17', '722'),
(146, '2705988331444295', '2027-04-01', '626'),
(147, '1859478067171268', '2028-05-16', '266'),
(147, '2592205521558703', '2029-03-09', '801'),
(148, '9961753498326098', '2028-05-08', '470'),
(149, '1366992800761435', '2027-12-30', '062'),
(149, '6497032920889624', '2027-07-29', '329'),
(150, '2186905796544044', '2028-05-27', '110'),
(150, '3112945348761603', '2027-04-04', '577'),
(151, '3483316477438463', '2028-08-14', '761'),
(151, '1911916897995826', '2027-12-15', '513'),
(152, '4194218888853848', '2029-04-25', '804'),
(153, '8405914857953318', '2030-01-09', '089'),
(154, '4563309033269716', '2028-02-29', '455'),
(154, '8375345331687084', '2028-11-22', '951'),
(154, '1066470803013936', '2030-01-15', '867'),
(155, '9438068216815654', '2029-09-23', '045'),
(155, '8241909746416121', '2029-05-16', '030'),
(155, '6320062715321804', '2029-01-21', '917'),
(156, '0550139863775372', '2028-08-25', '801'),
(157, '9853199966725311', '2028-01-04', '176'),
(157, '1799666897255749', '2029-11-18', '838'),
(157, '6930562659826913', '2027-09-03', '275'),
(158, '1057070924533626', '2029-06-10', '442'),
(158, '1540060509169024', '2029-04-17', '014'),
(158, '5774225872737193', '2029-08-22', '362'),
(159, '5770729805545811', '2029-08-08', '718'),
(159, '2366289090934894', '2029-03-15', '062'),
(160, '7359196685733975', '2029-04-27', '690'),
(160, '9473029342302010', '2029-08-24', '235'),
(160, '7521303858914405', '2028-10-02', '377'),
(161, '7003858155134930', '2029-08-28', '312'),
(161, '5478191093499408', '2028-03-30', '774'),
(162, '2680160862987326', '2029-08-29', '499'),
(162, '8959598801160829', '2028-04-03', '391'),
(162, '8484631628888793', '2027-04-01', '898'),
(163, '7532457338164342', '2028-08-24', '069'),
(163, '1987609635767788', '2028-08-27', '993'),
(163, '4676863743909298', '2029-01-18', '933'),
(164, '8237661233913457', '2029-06-27', '729'),
(164, '1480865372166130', '2029-04-03', '261'),
(165, '7074309504426123', '2028-09-16', '173'),
(165, '9965498641069778', '2029-12-10', '907'),
(165, '6031800500964950', '2028-02-28', '227'),
(166, '7798994082690335', '2027-10-04', '166'),
(167, '6392543375015140', '2029-03-03', '220'),
(167, '6065401162587039', '2029-12-28', '970'),
(168, '0740701777429349', '2029-12-27', '549'),
(168, '1438721914949573', '2027-09-11', '942'),
(168, '1651451385857106', '2027-07-07', '934'),
(169, '0208574050092196', '2027-07-07', '599'),
(169, '0587026847694040', '2028-04-03', '004'),
(169, '1675512834179363', '2027-09-06', '679'),
(170, '9356927571501322', '2028-03-26', '865'),
(170, '4836905520016543', '2027-07-07', '215'),
(170, '0395898946041083', '2028-06-21', '628'),
(171, '5069810805937929', '2029-10-11', '694'),
(171, '7979967612250745', '2028-12-14', '957'),
(172, '7977522825901276', '2029-12-22', '323'),
(172, '9021062932458008', '2028-05-17', '078'),
(172, '6943334574170495', '2029-05-21', '403'),
(173, '5165423901349222', '2027-07-11', '289'),
(173, '3842414024404650', '2029-03-29', '947'),
(174, '6212611682516744', '2027-06-11', '604'),
(175, '6262091306705055', '2029-12-04', '785'),
(175, '6599445185114423', '2028-04-07', '291'),
(176, '5025458399901121', '2028-10-15', '003'),
(176, '4528642460058407', '2027-08-28', '264'),
(177, '9547050217806585', '2029-08-07', '862'),
(177, '8957242350640661', '2027-04-25', '063'),
(177, '0721706704806188', '2027-11-23', '246'),
(178, '2360797733021918', '2027-05-13', '742'),
(178, '8045326634094346', '2027-12-15', '412'),
(178, '3623566848489540', '2028-08-13', '639'),
(179, '8557681767194473', '2027-10-11', '292'),
(180, '1175711986418269', '2028-06-09', '803'),
(181, '0847021761862738', '2028-01-19', '117'),
(181, '4007035080549681', '2028-06-14', '646'),
(181, '6532492496837537', '2028-10-05', '507'),
(182, '4118216538747851', '2028-05-15', '479'),
(183, '4838541478187358', '2028-10-17', '104'),
(184, '3868141131225144', '2028-07-03', '438'),
(184, '6823940168390707', '2028-09-01', '577'),
(184, '8001237975237418', '2029-12-29', '660'),
(185, '0989420247352922', '2028-02-25', '832'),
(186, '6524780812629072', '2029-10-14', '063'),
(186, '6115904686439151', '2027-06-26', '628'),
(187, '1805411427460896', '2028-05-08', '469'),
(188, '1485895436357308', '2028-05-29', '333'),
(188, '9606296097133724', '2027-04-19', '141'),
(189, '6991304615091011', '2028-12-06', '189'),
(190, '4699906696256781', '2029-12-12', '163'),
(191, '6019191001233973', '2028-07-19', '514'),
(191, '3051957593892451', '2027-12-08', '223'),
(192, '1092992487559095', '2028-01-30', '822'),
(193, '7093710887485751', '2028-09-03', '184'),
(194, '5289405049417407', '2029-05-07', '626'),
(194, '3815301904401300', '2027-02-27', '859'),
(195, '6251297102375020', '2027-10-17', '237'),
(196, '8412181118312576', '2029-01-05', '353'),
(196, '4142919466247355', '2028-12-14', '556'),
(197, '6454025702946712', '2027-09-25', '182'),
(197, '5177878458686996', '2027-07-28', '364'),
(198, '3173081538199045', '2027-10-17', '261'),
(199, '0874093334731434', '2027-03-14', '800'),
(200, '1794474592389955', '2028-09-18', '298'),
(200, '7242256769215017', '2027-09-23', '822'),
(201, '9584793307882939', '2030-02-08', '975'),
(201, '9842095540082688', '2028-01-18', '876'),
(202, '0366088067618192', '2028-02-07', '301'),
(202, '0756632468515940', '2029-01-20', '004'),
(203, '6690852600588007', '2027-05-25', '437'),
(204, '0132109331914039', '2029-02-09', '767'),
(205, '9586137441847999', '2027-11-01', '134'),
(205, '5490693392320208', '2029-04-30', '988'),
(206, '6772061532453821', '2027-02-23', '567'),
(206, '7322098528214755', '2028-08-31', '556'),
(206, '7207958088764144', '2028-12-25', '274'),
(207, '8559699487342035', '2029-01-10', '833'),
(208, '8745776363893538', '2028-08-03', '743'),
(208, '4742446618249069', '2028-03-12', '958'),
(209, '5728364617599494', '2027-07-28', '518'),
(209, '8028403484320061', '2029-10-27', '896'),
(209, '0856601712320706', '2029-11-11', '889'),
(210, '7924693251789566', '2027-08-04', '578'),
(211, '0153100625464482', '2027-11-25', '129'),
(212, '1274122999771300', '2030-01-10', '110'),
(213, '1099814624068353', '2029-11-21', '280'),
(213, '2103048951713916', '2027-09-27', '653'),
(213, '8961364325182062', '2028-12-26', '412'),
(214, '2772813177784388', '2029-12-01', '608'),
(215, '0597890449028340', '2027-12-05', '165'),
(215, '1529456969729691', '2028-08-15', '503'),
(216, '3087315935510691', '2027-07-14', '774'),
(217, '5662231322644979', '2028-08-19', '450'),
(218, '4366917477456464', '2029-08-02', '594'),
(218, '4795336554108952', '2029-08-29', '363'),
(218, '8327384220519372', '2029-10-08', '783'),
(219, '5936032128488178', '2027-07-27', '523'),
(220, '5112423719261509', '2027-09-03', '548'),
(220, '7773716508913963', '2029-09-15', '695'),
(221, '4924534474970436', '2027-11-13', '427'),
(221, '3322574266373152', '2029-10-26', '337'),
(221, '2416594528664276', '2027-09-05', '679'),
(222, '5130446028947119', '2027-07-28', '826'),
(222, '3148556195186114', '2027-05-03', '890'),
(222, '4768098463250659', '2028-07-14', '251'),
(223, '5895864090908717', '2027-05-07', '058'),
(223, '0280931222569811', '2028-10-20', '422'),
(223, '1613012870345857', '2029-02-07', '829'),
(224, '5862692718981895', '2029-08-26', '403'),
(224, '0735129219635713', '2028-06-02', '536'),
(225, '5661363979976069', '2027-10-26', '918'),
(225, '0487577601053611', '2029-12-01', '561'),
(225, '8263193351303806', '2028-06-11', '121'),
(226, '8918197412249197', '2029-09-24', '117'),
(227, '6595710936400743', '2028-06-07', '939'),
(228, '3519604215918161', '2029-08-30', '169'),
(229, '5254257838503738', '2028-11-09', '015'),
(230, '3592885685558793', '2029-10-06', '526'),
(230, '8656199454481543', '2027-09-21', '210'),
(230, '3729241229601800', '2030-01-25', '288'),
(231, '0739684904191418', '2028-04-01', '826'),
(232, '0801437407399853', '2027-06-18', '460'),
(232, '8443856177894022', '2029-04-23', '268'),
(232, '5099851183844974', '2027-11-20', '367'),
(233, '7195139748554224', '2029-06-01', '200'),
(234, '2523119070126008', '2030-01-29', '084'),
(235, '8122404826017362', '2027-06-22', '905'),
(235, '3288231103109494', '2030-02-21', '350'),
(235, '5125476384182675', '2029-09-21', '798'),
(236, '2245196144249058', '2028-08-27', '252'),
(236, '3563786202650692', '2028-10-20', '830'),
(236, '4968111248158112', '2027-06-22', '138'),
(237, '7112544795577490', '2027-12-06', '036'),
(237, '1712636374692364', '2027-02-23', '908'),
(237, '5792087366967108', '2028-12-17', '611'),
(238, '6780202080196764', '2028-11-28', '203'),
(238, '0940076155135061', '2029-05-01', '400'),
(239, '6875158087229387', '2028-03-12', '723'),
(239, '9377676555654522', '2027-06-29', '212'),
(240, '3930795668577027', '2029-08-22', '595'),
(240, '1011940189618605', '2027-06-02', '034'),
(241, '8139684903487284', '2028-01-27', '680'),
(241, '6149193689327317', '2030-02-09', '650'),
(241, '5673650755278105', '2027-11-24', '450'),
(242, '5164432135325200', '2028-07-27', '318'),
(242, '2640019538424473', '2029-01-28', '243'),
(242, '5699387365503428', '2028-06-03', '601'),
(243, '3294378470823975', '2027-06-27', '870'),
(243, '3702327724503571', '2027-12-18', '442'),
(243, '6008012546739547', '2027-08-25', '006'),
(244, '1982711858058119', '2027-05-09', '740'),
(245, '6998067624757240', '2029-04-13', '273'),
(245, '4838465297401271', '2029-08-05', '827'),
(245, '1230441324378158', '2027-03-08', '034'),
(246, '1931159542960787', '2028-01-29', '719'),
(246, '4766821858826232', '2028-05-03', '212'),
(247, '4113771187499609', '2027-09-04', '962'),
(248, '5997173036862826', '2028-05-21', '871'),
(249, '5706059145861818', '2027-05-22', '170'),
(249, '7870305321732328', '2028-07-16', '880'),
(250, '3650453845338976', '2028-09-14', '074'),
(250, '6936558691701826', '2030-01-11', '529'),
(251, '1319268564255198', '2029-10-13', '958'),
(252, '5877472295094008', '2028-01-26', '123'),
(253, '9189675667587197', '2029-08-19', '685'),
(253, '9835223815358338', '2027-09-29', '152'),
(253, '0252265774800783', '2027-08-06', '477'),
(254, '8969018335325269', '2028-01-10', '856'),
(255, '1107061305281448', '2028-07-15', '515'),
(255, '9317190168004974', '2029-01-27', '149'),
(255, '8338629747965807', '2029-05-25', '116'),
(256, '3257123164227048', '2028-11-13', '705'),
(257, '4416363529500825', '2027-09-09', '470'),
(258, '9155769521716110', '2028-10-08', '239'),
(258, '1001655641898069', '2030-01-04', '113'),
(258, '8190613507584834', '2027-08-20', '311'),
(259, '1637877437040963', '2028-11-01', '853'),
(259, '4840515048302669', '2028-11-27', '575'),
(259, '0157464217096414', '2029-04-03', '930'),
(260, '7616862748615703', '2028-11-14', '489'),
(261, '2859904973973073', '2028-01-26', '588'),
(262, '4777892296740672', '2029-08-01', '110'),
(263, '8180290473642981', '2029-08-28', '213'),
(263, '0532537507415577', '2027-08-09', '436'),
(263, '9777742164399246', '2029-02-22', '830'),
(264, '2196983587178293', '2029-07-28', '381'),
(265, '2046113209152928', '2027-03-12', '191'),
(266, '9809442337138327', '2027-12-18', '137'),
(267, '2839745386654732', '2027-07-14', '899'),
(268, '5608085688557150', '2029-11-25', '514'),
(269, '4807719300243114', '2029-05-11', '970'),
(270, '9306220048357512', '2029-09-29', '536'),
(270, '9671774826381767', '2028-06-04', '519'),
(270, '6102043696486479', '2029-06-18', '317'),
(271, '3094639091898858', '2028-08-23', '639'),
(271, '8901453342116259', '2028-08-14', '385'),
(271, '2459436244579908', '2029-08-17', '660'),
(272, '3519132412826264', '2029-03-02', '307'),
(272, '5328117366554590', '2028-07-21', '444'),
(272, '3153934337885994', '2027-05-14', '192'),
(273, '8167350773250553', '2028-04-19', '959'),
(273, '1181138734977122', '2029-02-04', '671'),
(273, '7890366140405239', '2029-03-09', '730'),
(274, '3482843643945588', '2028-07-22', '078'),
(275, '2079234768255936', '2027-06-26', '741'),
(275, '8259794568786509', '2028-08-16', '366'),
(275, '3595632477266253', '2028-10-07', '523'),
(276, '1674938731783367', '2027-08-07', '690'),
(277, '4249305535910064', '2029-02-28', '195'),
(277, '3639638270480916', '2029-01-18', '622'),
(278, '9040567632455833', '2029-11-21', '992'),
(278, '5059383203656811', '2029-02-15', '811'),
(279, '6287542497199240', '2028-05-16', '401'),
(280, '3239039901354237', '2028-06-15', '734'),
(281, '1632363026084899', '2027-05-17', '164'),
(281, '3039079643413139', '2028-04-10', '742'),
(282, '2220800361989319', '2028-02-14', '366'),
(282, '3127702101920492', '2027-06-06', '774'),
(283, '9193926123566451', '2028-09-30', '903'),
(284, '5996324393171379', '2027-03-25', '915'),
(284, '6495115158929251', '2028-09-20', '905'),
(285, '6237410160867790', '2029-04-27', '889'),
(286, '0602880091017968', '2029-11-06', '530'),
(286, '0508569557926457', '2027-10-27', '152'),
(287, '2617830346523647', '2029-08-19', '207'),
(287, '1610953017308086', '2029-08-25', '749'),
(288, '5497403597330545', '2027-06-05', '854'),
(288, '3835856367695410', '2029-09-17', '597'),
(289, '8740152644101616', '2029-08-23', '444'),
(289, '3089147822113192', '2028-01-21', '782'),
(289, '2534708200061623', '2028-10-02', '456'),
(290, '2710092838914951', '2028-02-01', '553'),
(290, '8364961653111019', '2029-05-29', '795'),
(290, '7675404100670824', '2030-02-16', '065'),
(291, '8453386866207850', '2027-04-12', '006'),
(291, '8718217026596391', '2028-07-29', '092'),
(291, '2193215901668244', '2027-11-28', '582'),
(292, '6360437767910804', '2028-09-30', '020'),
(292, '5977092831779171', '2028-02-12', '028'),
(293, '9422440385268255', '2027-06-05', '604'),
(293, '7354609800418675', '2028-01-17', '264'),
(294, '7558711771317502', '2029-10-17', '157'),
(294, '5869210028048688', '2029-01-02', '794'),
(294, '6406880465240050', '2027-02-27', '771'),
(295, '8374226945562269', '2027-07-08', '555'),
(295, '0263603193425754', '2028-08-28', '220'),
(295, '6710763481789906', '2028-03-29', '117'),
(296, '7138850644556170', '2028-02-17', '130'),
(297, '8388435903600329', '2027-04-17', '208'),
(298, '5948977265234024', '2029-02-11', '220'),
(298, '3711718329981654', '2029-04-04', '102'),
(299, '3801178595213747', '2028-01-04', '093'),
(299, '5635975906921208', '2028-03-29', '170'),
(299, '0046006188306585', '2029-03-07', '929'),
(300, '2734325450411840', '2028-04-26', '746'),
(301, '8922797498495646', '2028-07-15', '611'),
(301, '3910233892235041', '2029-06-27', '018'),
(302, '5828505353017139', '2028-10-22', '890'),
(302, '7203842358851745', '2028-12-12', '726'),
(302, '8915740542105119', '2028-08-25', '153'),
(303, '1778078816222589', '2030-01-02', '943'),
(303, '1835835104208765', '2027-12-21', '576'),
(303, '2533562294388506', '2029-10-06', '718'),
(304, '7699291161420281', '2027-05-10', '100'),
(304, '8844322491874810', '2028-04-23', '372'),
(304, '8903933571629324', '2028-04-08', '727'),
(305, '8194915857609546', '2027-09-17', '627'),
(306, '6499058032676138', '2029-12-31', '825'),
(307, '1517257882608176', '2027-05-31', '065'),
(307, '8106233396025999', '2029-08-03', '902'),
(308, '9054531145764163', '2028-09-23', '073'),
(308, '2146467410845841', '2028-05-10', '131'),
(308, '6696449191793824', '2029-04-27', '340'),
(309, '9628416366576508', '2029-07-31', '469'),
(309, '4009761658168246', '2029-07-12', '208'),
(309, '0641228091959833', '2029-04-03', '988'),
(310, '6276920227614783', '2028-09-03', '763'),
(310, '5474408069594583', '2028-04-12', '795'),
(311, '6426060974960001', '2028-01-25', '046'),
(311, '2267055806105747', '2028-01-30', '596'),
(311, '7669474424430706', '2029-05-25', '783'),
(312, '0731125682377339', '2028-01-05', '095'),
(312, '6887916868742174', '2030-01-06', '732'),
(313, '6224333869270936', '2028-03-03', '911'),
(313, '1740328890360072', '2028-11-16', '513'),
(314, '2867486683382236', '2027-10-15', '984'),
(314, '2324435602223374', '2028-05-03', '579'),
(314, '7876938869435393', '2028-02-19', '120'),
(315, '8624351408672811', '2029-04-28', '395'),
(315, '5712366427070192', '2028-02-05', '438'),
(315, '5973674172891058', '2028-08-09', '987'),
(316, '7462175000680081', '2028-09-27', '097'),
(317, '1787579206238729', '2028-07-18', '111'),
(318, '1998436143266838', '2028-04-16', '202'),
(318, '8506789895791905', '2029-06-19', '247'),
(319, '7740132678660769', '2028-04-21', '038'),
(319, '2636767169892215', '2027-05-19', '636'),
(320, '2636320045432237', '2030-02-15', '878'),
(321, '5155733128288005', '2027-10-18', '705'),
(321, '4799082717704265', '2029-10-15', '602'),
(321, '0360282480615214', '2027-10-13', '842'),
(322, '5711854361163497', '2029-01-23', '317'),
(323, '9570999080447056', '2028-04-25', '053'),
(323, '5913237602642775', '2028-02-28', '372'),
(324, '6148420123012157', '2029-11-17', '305'),
(324, '6252478307567558', '2028-01-10', '705'),
(324, '0999128780670401', '2028-12-20', '258'),
(325, '1742194937558676', '2027-11-09', '010'),
(326, '1941627339498691', '2029-11-09', '576'),
(327, '9059201582530799', '2028-06-09', '315'),
(328, '2170826769093244', '2028-10-03', '471'),
(328, '3071282086026088', '2027-12-26', '518'),
(329, '1787139282249239', '2028-07-05', '545'),
(329, '3835097163126810', '2029-12-22', '965'),
(329, '3874821381030050', '2029-03-11', '830'),
(330, '1975252631622997', '2029-11-08', '115'),
(330, '2618845259865357', '2028-02-16', '446'),
(330, '3242120751202355', '2027-08-29', '594'),
(331, '4270960852245104', '2028-03-29', '706'),
(331, '0113570678354870', '2030-02-15', '690'),
(332, '4055640594914439', '2028-07-06', '426'),
(333, '4929492197836301', '2028-10-30', '364'),
(333, '1567226914378226', '2027-11-11', '212'),
(333, '5538649730479631', '2028-02-26', '300'),
(334, '4674094668765018', '2027-11-03', '037'),
(335, '8881232259434016', '2029-05-23', '815'),
(335, '4085255052421499', '2028-05-05', '340'),
(336, '6674356766493893', '2028-11-21', '359'),
(336, '5574098069280605', '2029-04-21', '965'),
(337, '7767861168769839', '2029-06-01', '155'),
(337, '9522654863972334', '2027-07-08', '285'),
(337, '7974954036073156', '2029-01-02', '270'),
(338, '7428770741226809', '2030-02-22', '306'),
(338, '7752780055445507', '2030-01-01', '652'),
(338, '4690093949953679', '2029-01-15', '382'),
(339, '5561998579128013', '2028-12-03', '175'),
(340, '4315801841728580', '2030-01-09', '042'),
(340, '8702621700986826', '2027-08-12', '112'),
(340, '9829669843423104', '2029-02-11', '330'),
(341, '9642110255164783', '2029-07-28', '812'),
(342, '0594295493861894', '2027-06-17', '866'),
(343, '2499052947964262', '2029-09-15', '165'),
(344, '1391297137801939', '2029-07-12', '423'),
(345, '0649752769793193', '2028-12-04', '777'),
(345, '4091177287455470', '2027-03-10', '289'),
(346, '9128717439001201', '2030-02-12', '205'),
(347, '8309816526759696', '2029-05-30', '058'),
(348, '1886749681210244', '2029-02-20', '309'),
(348, '3113764013071467', '2028-07-20', '882'),
(349, '7164805620511405', '2029-08-10', '139'),
(349, '9104882521439681', '2027-08-24', '685'),
(350, '4950957347529497', '2027-09-23', '441'),
(350, '1342666695787247', '2028-03-06', '457'),
(350, '4983230102339185', '2029-05-30', '537'),
(351, '4425578876182069', '2029-12-29', '832'),
(351, '7225750358775425', '2029-12-06', '317'),
(351, '6269877144845302', '2028-12-24', '861'),
(352, '8035795410842523', '2028-06-20', '939'),
(352, '2608987794032339', '2029-02-11', '406'),
(352, '9333939361153850', '2029-09-04', '681'),
(353, '2885938379160879', '2027-04-25', '496'),
(353, '8093545836559557', '2027-06-26', '335'),
(354, '0898216618127097', '2028-08-29', '697'),
(354, '3790772930852323', '2028-05-30', '925'),
(355, '1270048779426094', '2027-07-27', '860'),
(355, '3828030354773712', '2029-02-13', '095'),
(355, '0962360789926886', '2028-03-30', '842'),
(356, '4272609332908509', '2027-02-28', '595'),
(356, '3707371880632656', '2028-10-01', '240'),
(357, '1799795847214355', '2027-12-05', '569'),
(358, '0774247036340897', '2029-11-05', '545'),
(358, '6404567986025040', '2029-08-07', '489'),
(359, '6182427377615331', '2028-12-12', '104'),
(360, '7400656283128097', '2027-06-08', '338'),
(360, '4747553107537366', '2028-12-31', '848'),
(360, '4684414123357248', '2029-09-23', '983'),
(361, '4854326623437845', '2027-10-24', '220'),
(361, '3258909871390261', '2028-11-28', '878'),
(361, '8382606639003547', '2027-05-19', '758'),
(362, '5894813329328840', '2027-09-27', '467'),
(362, '1187601293116014', '2027-11-30', '825'),
(363, '6850883357830850', '2028-02-10', '819'),
(364, '7867567213314300', '2028-07-03', '513'),
(365, '2376348898708163', '2027-06-27', '334'),
(365, '9477830196658597', '2029-04-25', '154'),
(365, '7567208426353959', '2028-01-25', '130'),
(366, '9675926798462706', '2029-10-16', '328'),
(366, '4243752056699218', '2030-01-31', '809'),
(366, '6536973775963101', '2027-12-06', '035'),
(367, '5828538332547411', '2029-01-13', '385'),
(367, '4698153487647011', '2028-04-17', '718'),
(368, '4534503971757098', '2029-07-01', '129'),
(368, '1039325080284484', '2027-11-07', '528'),
(369, '3131494854148426', '2029-03-22', '573'),
(369, '6956507694109157', '2028-12-20', '775'),
(370, '2344263189772380', '2029-05-03', '691'),
(370, '5790977307689230', '2029-10-01', '288'),
(371, '9784795868379535', '2028-03-05', '246'),
(371, '5058058786051165', '2028-05-13', '730'),
(371, '3486921461234160', '2029-11-13', '151'),
(372, '1636434945352479', '2029-12-29', '253'),
(372, '7114910008892345', '2027-12-30', '901'),
(372, '6035788733268463', '2027-09-19', '083'),
(373, '0859697767339032', '2028-04-06', '928'),
(373, '4434573023516105', '2028-07-23', '310'),
(374, '1464600365755413', '2028-08-21', '470'),
(374, '7089044773862486', '2029-05-09', '871'),
(374, '7568297653824378', '2028-09-10', '020'),
(375, '6094346233010640', '2028-09-13', '354'),
(375, '3672639118129281', '2029-02-01', '361'),
(375, '9752447885722830', '2027-08-22', '056'),
(376, '4409631901450167', '2028-03-28', '126'),
(376, '5821672198232175', '2030-01-13', '577'),
(376, '0623629699990894', '2027-06-02', '729'),
(377, '4075961086809919', '2029-02-10', '622'),
(378, '0805657214189850', '2028-08-21', '741'),
(378, '7311012513192639', '2028-08-16', '560'),
(378, '0152344533289256', '2028-03-05', '073'),
(379, '6129729662658659', '2028-06-16', '002'),
(379, '0292239602555290', '2027-03-27', '098'),
(379, '2238043347155400', '2027-07-25', '652'),
(380, '8079725353678502', '2027-07-19', '102'),
(381, '5236944421153738', '2029-05-26', '979'),
(381, '7824016819201837', '2029-12-16', '433'),
(381, '7470107427184254', '2027-11-20', '895'),
(382, '2909179360252114', '2029-09-18', '888'),
(382, '5004683990150131', '2029-08-16', '837'),
(383, '7709252457119623', '2027-07-29', '828'),
(383, '7077185462027292', '2029-06-07', '049'),
(384, '4799799253228230', '2029-08-10', '949'),
(385, '7420824991791134', '2029-10-19', '764'),
(386, '8998101666517050', '2028-07-27', '910'),
(387, '8179701159571804', '2027-05-14', '969'),
(388, '9646965394487838', '2028-04-29', '406'),
(389, '4470316406354695', '2027-11-15', '639'),
(389, '4109320353609041', '2028-07-02', '636'),
(389, '4003072669747232', '2029-06-30', '173'),
(390, '8106739741654568', '2028-09-09', '419'),
(390, '2510057960607487', '2029-08-21', '753'),
(391, '2927110742521983', '2028-03-05', '973'),
(391, '4985460031699483', '2027-03-22', '302'),
(392, '4090571972090723', '2029-09-04', '157'),
(392, '2002647211776981', '2028-10-30', '659'),
(392, '1898824953899864', '2027-07-10', '268'),
(393, '2500653177300833', '2029-09-08', '542'),
(393, '4193687654993720', '2027-12-29', '281'),
(393, '3448326712578014', '2028-11-28', '583'),
(394, '0777815698331151', '2028-12-07', '405'),
(394, '7141184353318492', '2029-03-27', '628'),
(395, '6942670041764766', '2029-05-18', '563'),
(396, '8040454964824552', '2028-06-17', '313'),
(397, '0958232062262258', '2027-08-16', '206'),
(398, '4717172815724710', '2027-12-29', '488'),
(399, '8729639507021262', '2028-10-19', '487'),
(399, '0249124323988848', '2029-09-27', '958'),
(400, '6634343984926377', '2029-12-28', '781'),
(401, '7488972182312229', '2027-12-09', '390'),
(401, '7663369180071320', '2029-12-19', '193'),
(401, '4340931015975766', '2029-11-04', '552'),
(402, '3279675586003425', '2029-10-03', '298'),
(402, '3128297654340195', '2027-08-21', '241'),
(403, '6292230393422575', '2027-10-27', '625'),
(403, '9329465265091730', '2028-04-02', '319'),
(404, '4648751757511394', '2029-12-05', '799'),
(404, '0894464687710466', '2028-10-11', '751'),
(405, '3292464893814816', '2027-08-04', '714'),
(406, '3682822642357620', '2028-02-23', '882'),
(407, '6913222529702024', '2029-04-24', '926'),
(407, '2830494697895820', '2030-02-02', '794'),
(407, '0259970182848195', '2029-02-16', '598'),
(408, '2895824222416914', '2027-04-28', '767'),
(408, '4958890097238018', '2028-11-06', '204'),
(409, '3743383633485990', '2029-06-10', '355'),
(409, '1099994519665590', '2029-04-03', '895'),
(410, '3834983320537311', '2029-06-01', '473'),
(411, '9016781691026394', '2029-09-17', '909'),
(411, '2318018704047936', '2030-01-06', '785'),
(412, '5464285114631266', '2027-03-28', '494'),
(412, '7967751457943215', '2028-11-03', '963'),
(413, '2176331085423838', '2027-10-23', '790'),
(414, '4567841288486639', '2027-10-03', '745'),
(414, '4111034873735808', '2028-05-18', '089'),
(414, '8092529356257182', '2028-12-08', '959'),
(415, '5397331241131406', '2028-06-14', '649'),
(415, '4716354991556587', '2027-10-06', '643'),
(416, '0908303021777801', '2029-12-07', '723'),
(416, '3163332174202261', '2029-04-23', '355'),
(416, '3890763596324248', '2028-02-15', '179'),
(417, '4687600498741783', '2027-11-04', '010'),
(418, '6324964371711469', '2029-07-08', '524'),
(418, '4707024763690699', '2029-02-21', '257'),
(418, '8734562445811780', '2029-09-02', '051'),
(419, '6049321028402511', '2028-07-20', '023'),
(419, '6048994821218476', '2029-07-31', '676'),
(419, '4096613595658325', '2028-10-14', '032'),
(420, '9769525649272992', '2029-03-02', '907'),
(420, '2696319581493665', '2028-05-03', '444'),
(420, '9225138897642854', '2027-04-28', '006'),
(421, '0368498319163745', '2030-01-03', '095'),
(421, '7873079708139841', '2027-09-28', '759'),
(421, '3219402467232583', '2027-04-07', '535'),
(422, '7168644142239189', '2029-09-03', '998'),
(422, '3630001063767965', '2029-02-12', '978'),
(423, '7985645054526045', '2027-03-23', '428'),
(424, '7154775683454488', '2029-05-03', '463'),
(424, '5717460203642671', '2028-02-26', '636'),
(425, '8430575700205398', '2028-01-07', '629'),
(426, '9304399620646647', '2027-08-25', '303'),
(426, '4830268153456246', '2028-05-28', '994'),
(426, '0674361557500674', '2029-10-14', '906'),
(427, '7197452987789816', '2027-08-13', '937'),
(427, '7390174726817799', '2028-01-03', '512'),
(427, '3688407003953636', '2029-12-26', '035'),
(428, '6213055325339264', '2028-06-08', '343'),
(428, '3698881847002027', '2029-04-24', '097'),
(428, '4409307543802906', '2027-03-17', '579'),
(429, '1212846254594327', '2029-10-24', '094'),
(429, '6015168580160190', '2028-03-18', '975'),
(430, '8237703850647893', '2029-06-15', '404'),
(431, '7233739628779460', '2029-10-03', '778'),
(432, '8996092087073251', '2027-10-06', '955'),
(432, '8340419259936618', '2028-02-01', '071'),
(432, '1417624930216679', '2027-06-18', '203'),
(433, '9488490950703769', '2029-05-18', '214'),
(433, '7385453884275488', '2029-05-24', '046'),
(434, '1085104238237890', '2029-03-21', '926'),
(434, '1185427310472974', '2028-08-16', '652'),
(435, '1498642816966515', '2029-12-13', '667'),
(436, '7822383639469260', '2028-04-09', '734'),
(437, '2393429331139942', '2029-09-29', '528'),
(437, '1606969182453799', '2029-02-27', '546'),
(438, '5787529559541281', '2028-12-17', '228'),
(438, '5624126384331087', '2029-06-13', '924'),
(438, '6977796848541001', '2027-12-03', '820'),
(439, '8598878543589505', '2030-02-05', '133'),
(439, '7416228226002033', '2030-01-14', '324'),
(439, '1774261074675153', '2028-06-16', '334'),
(440, '6318186228883716', '2029-11-01', '571'),
(440, '2278931105877671', '2027-10-02', '840'),
(440, '0720331114388062', '2028-01-27', '185'),
(441, '9916401251272461', '2027-03-30', '172'),
(442, '1657593237407105', '2028-02-11', '515'),
(442, '7921963755160953', '2027-05-14', '847'),
(442, '6960708889631166', '2029-11-18', '219'),
(443, '9615644267140039', '2029-01-23', '967'),
(443, '2937444833994110', '2029-12-06', '840'),
(443, '6128466743123969', '2028-04-26', '315'),
(444, '9887317874094868', '2029-11-18', '260'),
(444, '2460716766855224', '2027-07-24', '139'),
(445, '6056244001345389', '2027-05-02', '076'),
(445, '8283749894555442', '2029-01-08', '272'),
(445, '8655357511291520', '2029-06-24', '594'),
(446, '5285941598995408', '2028-04-29', '314'),
(446, '7802121443387401', '2028-10-17', '889'),
(447, '9558266238581195', '2029-05-03', '834'),
(447, '1892900794200953', '2029-06-26', '499'),
(447, '1857116775771282', '2027-06-09', '478'),
(448, '7355377425265994', '2027-08-15', '126'),
(449, '3101147273132677', '2028-08-11', '338'),
(449, '7901040176327504', '2029-03-23', '860'),
(450, '2052871647396892', '2029-11-28', '362'),
(450, '2341927804701888', '2030-02-15', '497'),
(451, '1008757294466449', '2029-03-23', '518'),
(452, '5422102883628133', '2027-07-26', '805'),
(452, '2409101040186887', '2027-08-23', '031'),
(452, '4028156569088509', '2029-07-05', '914'),
(453, '2249432182226470', '2029-09-19', '829'),
(453, '1117732682426203', '2030-02-15', '187'),
(453, '8637302024916376', '2029-01-28', '252'),
(454, '5513186979645202', '2027-04-19', '105'),
(454, '0444079592064702', '2027-08-29', '133'),
(454, '9643665135096745', '2027-09-23', '900'),
(455, '9342837918829499', '2027-12-15', '888'),
(455, '4955278787778816', '2027-10-06', '228'),
(456, '2731039206158961', '2027-09-28', '943'),
(456, '8754659085323451', '2027-08-19', '064'),
(456, '1391777037699350', '2027-09-21', '548'),
(457, '3059138712969020', '2028-01-15', '867'),
(458, '1052837611770485', '2028-09-04', '520'),
(458, '2809108473924805', '2028-02-17', '365'),
(459, '3670457206607854', '2029-10-04', '889'),
(459, '7950061663927359', '2029-05-03', '038'),
(459, '0962408545339568', '2029-06-24', '929'),
(460, '0911402535432036', '2027-04-02', '502'),
(460, '9130430010845727', '2028-04-04', '292'),
(460, '3674901254954072', '2029-08-01', '201'),
(461, '1925557274799792', '2027-09-08', '783'),
(461, '9236336599545101', '2027-10-06', '427'),
(461, '3032312240378948', '2029-02-11', '503'),
(462, '2372586895929681', '2029-08-01', '261'),
(462, '0451257863723506', '2028-01-04', '929'),
(463, '0504284101843523', '2029-05-19', '437'),
(464, '9131873289451415', '2028-06-18', '305'),
(464, '8764409108665414', '2029-05-12', '612'),
(465, '0134108044215234', '2027-08-19', '974'),
(465, '1948318969014524', '2027-09-18', '947'),
(465, '0617112424715250', '2029-01-26', '878'),
(466, '7183719498387192', '2029-02-08', '082'),
(466, '2270855980672575', '2028-01-04', '593'),
(466, '9477598493918249', '2027-05-17', '055'),
(467, '7412827972520725', '2028-07-14', '727'),
(467, '6702151944262824', '2027-03-08', '106'),
(468, '3416218796423620', '2027-11-14', '262'),
(468, '4589623014417899', '2029-08-24', '803'),
(468, '7621498004176362', '2028-06-01', '243'),
(469, '0317613443189912', '2028-08-23', '153'),
(469, '1341779318376136', '2028-10-01', '528'),
(470, '4664902373448517', '2029-08-14', '719'),
(471, '6896401156616384', '2028-08-30', '815'),
(472, '2797538917701430', '2028-10-03', '897'),
(473, '8578713017734761', '2029-01-19', '724'),
(473, '8733899387868658', '2027-11-01', '506'),
(473, '0890946376205751', '2029-11-17', '018'),
(474, '4992778996872445', '2028-07-06', '439'),
(475, '8723433864456976', '2027-04-11', '091'),
(475, '5319055191232416', '2029-08-28', '473'),
(476, '1353005382997433', '2028-04-11', '351'),
(476, '9890959395938573', '2028-08-23', '348'),
(477, '3083550023985058', '2029-05-25', '223'),
(477, '5695243080923021', '2029-04-03', '102'),
(477, '3726558534574816', '2029-09-17', '930'),
(478, '8403746879731931', '2028-10-13', '653'),
(479, '9117450097538248', '2029-05-15', '586'),
(479, '7716033356825639', '2029-08-15', '657'),
(480, '5207790945298192', '2030-02-07', '623'),
(480, '9132000279421226', '2028-09-07', '858'),
(480, '4162743615044815', '2028-05-31', '827'),
(481, '7637878880704733', '2029-08-13', '887'),
(482, '5831933844813455', '2030-01-16', '180'),
(483, '5813384434670162', '2028-07-17', '848'),
(484, '0660443169383687', '2027-04-16', '827'),
(484, '9762968902423054', '2028-04-24', '127'),
(485, '9411276962605790', '2030-01-19', '702'),
(485, '3945717166847116', '2028-08-11', '126'),
(485, '1653280713565568', '2027-09-27', '864'),
(486, '4598527516686001', '2029-01-05', '184'),
(486, '7376837656480183', '2027-03-11', '105'),
(487, '9940826879495183', '2028-03-09', '720'),
(488, '4532713082150956', '2028-04-17', '264'),
(488, '2470744912707397', '2027-06-30', '576'),
(489, '7080707436280457', '2027-12-06', '415'),
(489, '3700787087781713', '2029-07-03', '994'),
(489, '1647105762556225', '2030-02-17', '327'),
(490, '8670537954768328', '2029-05-15', '190'),
(491, '1945750044483544', '2028-02-23', '004'),
(492, '7144497643541366', '2028-11-20', '852'),
(493, '4013925293058982', '2029-12-07', '117'),
(493, '3262084526984948', '2029-10-06', '287'),
(493, '6360395423399342', '2028-10-15', '790'),
(494, '6991119780007171', '2029-04-15', '271'),
(494, '2402546189730048', '2029-10-10', '418'),
(494, '2184838234906419', '2028-07-24', '276'),
(495, '3475418513470302', '2028-07-12', '587'),
(495, '5716538404243051', '2029-02-27', '060'),
(495, '6589665546185351', '2029-04-21', '810'),
(496, '8387870562187981', '2029-01-27', '859'),
(496, '9365354520632087', '2029-12-18', '398'),
(497, '0314417676104119', '2027-06-21', '708'),
(497, '1876598785494968', '2027-10-25', '038'),
(497, '4570026636676646', '2029-07-01', '959'),
(498, '2202790499675191', '2028-08-11', '191'),
(498, '7493079714482968', '2027-06-12', '903'),
(499, '7443449599882320', '2027-08-27', '806'),
(499, '8178276812385869', '2029-08-28', '021'),
(500, '1662047769222056', '2029-07-07', '718'),
(501, '6053714694149734', '2028-03-31', '168'),
(501, '2818690778095697', '2028-04-29', '473'),
(502, '6962202429128278', '2029-01-21', '127'),
(502, '4537560917126731', '2028-06-06', '352'),
(503, '4498259040472682', '2029-06-13', '372'),
(504, '1622102039363200', '2028-03-19', '365'),
(504, '3503049372771297', '2027-12-01', '612'),
(505, '3468204567632511', '2029-12-23', '296'),
(505, '4095338133879475', '2030-02-05', '652'),
(505, '6130227345533198', '2028-08-21', '368'),
(506, '1897805678631324', '2027-08-27', '008'),
(507, '6576627402851752', '2028-12-22', '839'),
(508, '1922941526559618', '2028-11-07', '381'),
(509, '6721812575264602', '2027-09-01', '692'),
(509, '4998294351503518', '2027-11-27', '367'),
(510, '0834195750687378', '2029-09-18', '823'),
(511, '9066317761817372', '2027-12-13', '049'),
(511, '8484709873233614', '2029-11-21', '163'),
(511, '8994967519517717', '2028-09-12', '875'),
(512, '8672183731139515', '2029-12-28', '566'),
(513, '4899525603013573', '2029-12-12', '930'),
(513, '4229225152415738', '2028-06-23', '876'),
(513, '6874562875308653', '2029-02-27', '458'),
(514, '5526165055342733', '2030-02-06', '766'),
(514, '6822514247675669', '2027-03-21', '127'),
(514, '5864939394291979', '2027-10-08', '932'),
(515, '5746952806839192', '2027-04-07', '620'),
(515, '7938091258332545', '2027-08-19', '917'),
(515, '5183024226647957', '2028-06-17', '689'),
(516, '1762496457272954', '2027-06-04', '976'),
(516, '0683528884040495', '2029-11-18', '492'),
(516, '3055877839799473', '2027-11-08', '944'),
(517, '5578989276101775', '2027-10-30', '644'),
(517, '3427978448182357', '2028-03-26', '799'),
(517, '3401384329265633', '2027-08-28', '448'),
(518, '6503871283353546', '2030-02-04', '063'),
(519, '3473612866862038', '2027-03-22', '018'),
(520, '7664981822339072', '2028-12-10', '639'),
(520, '5093819857209256', '2028-03-05', '569'),
(521, '3018283277815604', '2027-05-27', '351'),
(521, '0031144100211072', '2027-03-01', '230'),
(522, '1202662638324937', '2028-02-08', '800'),
(522, '9924914241358995', '2027-11-25', '764'),
(523, '1380352830328068', '2029-05-22', '758'),
(523, '0637998921139591', '2027-08-28', '654'),
(523, '2512492454199723', '2029-03-03', '856'),
(524, '9786977473697378', '2027-07-26', '647'),
(524, '5137895161269087', '2028-04-10', '817'),
(524, '5759678543385263', '2029-12-28', '612'),
(525, '2740981079526849', '2027-10-19', '279'),
(525, '9401465651392512', '2029-05-19', '289'),
(526, '8560457030459299', '2028-04-15', '100'),
(527, '2553030619109274', '2028-03-03', '072'),
(528, '3368499649439025', '2028-04-07', '336'),
(529, '7332784607139485', '2027-09-05', '450'),
(530, '4455819142427311', '2029-12-10', '138'),
(530, '0589982896080772', '2028-07-25', '264'),
(530, '0427860611184444', '2029-10-16', '865'),
(531, '5574346497905667', '2027-03-28', '507'),
(531, '0746282407145937', '2028-06-26', '182'),
(531, '9012531162809456', '2029-11-07', '161'),
(532, '3946917245980701', '2029-10-27', '264'),
(532, '4659707522493016', '2027-03-05', '346'),
(532, '4301243410776739', '2029-01-23', '139'),
(533, '4934228042091990', '2027-12-20', '856'),
(534, '2575452595950640', '2030-02-12', '378'),
(535, '4733244131719799', '2027-11-03', '240'),
(536, '7158062578312186', '2028-03-23', '096'),
(536, '0258267929783196', '2030-01-17', '918'),
(537, '5063250400781250', '2027-08-29', '716'),
(538, '3647536874672352', '2028-02-25', '356'),
(538, '2542749325330350', '2027-08-13', '108'),
(539, '0613127303138235', '2028-01-16', '088'),
(539, '9096123988959918', '2028-09-04', '321'),
(539, '3952026985924662', '2028-05-18', '106'),
(540, '9985652455068667', '2029-10-08', '129'),
(541, '8859284216792207', '2029-06-14', '245'),
(541, '6373985308358736', '2029-01-21', '412'),
(542, '3512849060242552', '2030-02-11', '954'),
(543, '2696183603676957', '2028-08-02', '129'),
(543, '5372343393745367', '2028-12-22', '631'),
(543, '9659551744255129', '2029-03-03', '657'),
(544, '3683107050089120', '2029-03-26', '688'),
(544, '0013905412453231', '2029-07-05', '574'),
(545, '7590030076470217', '2028-07-23', '080'),
(545, '4024569976955768', '2028-03-18', '777'),
(546, '0505923868171326', '2028-12-06', '102'),
(547, '4596551555968336', '2028-11-26', '400'),
(547, '2661429359955027', '2029-11-22', '736'),
(547, '6983136701255618', '2030-01-31', '885'),
(548, '6471254933581132', '2029-07-05', '379'),
(549, '9141682718014351', '2027-11-22', '206'),
(549, '3898338770451996', '2029-06-19', '229'),
(549, '6675352361298635', '2028-10-13', '531'),
(550, '5505576410305540', '2029-03-21', '345'),
(550, '0719593507400709', '2028-12-05', '173'),
(550, '7768316119056833', '2027-09-02', '918'),
(551, '5150062843761598', '2028-05-15', '167'),
(551, '1646490232676850', '2027-02-23', '287'),
(552, '7495830540549726', '2029-06-02', '587'),
(553, '7444703748506816', '2029-08-03', '730'),
(553, '2437096751352274', '2029-08-21', '320'),
(554, '5701029292255737', '2028-07-27', '257'),
(554, '6099207709592779', '2028-10-13', '596'),
(554, '2109523027295971', '2029-07-05', '530'),
(555, '0143955056320015', '2027-04-13', '914'),
(555, '9942510714714448', '2028-12-18', '746'),
(555, '2863626361473051', '2029-11-11', '124'),
(556, '3997388303140411', '2028-07-20', '922'),
(556, '2918543270660283', '2027-12-30', '141'),
(557, '4176354006341459', '2029-02-07', '858'),
(557, '0019406065793541', '2029-01-21', '693'),
(558, '8039527610338649', '2030-01-22', '346'),
(558, '0305691258631747', '2029-05-26', '301'),
(559, '9655650585110242', '2030-02-19', '477'),
(559, '3771847804592464', '2028-02-25', '746'),
(560, '3891104089828368', '2027-06-17', '757'),
(560, '6488671265994536', '2029-01-31', '721'),
(560, '0866487463598513', '2029-07-01', '571'),
(561, '8283667617118130', '2029-03-31', '792'),
(562, '2793544232460654', '2028-09-15', '067'),
(563, '1021367908209077', '2027-12-31', '304'),
(564, '3387972478244295', '2027-11-03', '976'),
(564, '0413546494418147', '2027-12-15', '639'),
(564, '5489504446393355', '2029-04-22', '095'),
(565, '0044601245840270', '2028-11-17', '388'),
(566, '4289205265842962', '2028-03-11', '466'),
(567, '9047594067850794', '2029-04-19', '402'),
(567, '9777213518009430', '2028-04-12', '691'),
(568, '5257058926537170', '2028-11-29', '542'),
(568, '7516110925853337', '2028-12-23', '475'),
(569, '4497036227041313', '2028-07-26', '933'),
(570, '8536599205016905', '2029-08-29', '214'),
(571, '8877970011269301', '2027-06-12', '993'),
(571, '7729113857281159', '2028-10-21', '369'),
(571, '5417860925026451', '2027-07-07', '137'),
(572, '7664256489343673', '2030-01-30', '483'),
(572, '5851570084271072', '2029-11-21', '786'),
(573, '6003067746835573', '2027-03-26', '626'),
(573, '4856446221993364', '2027-11-17', '797'),
(573, '3392369335130444', '2028-12-25', '882'),
(574, '7868105545904036', '2028-01-06', '059'),
(575, '5440339972208589', '2028-01-04', '678'),
(575, '3530708940385328', '2027-08-09', '080'),
(576, '3400996371118648', '2027-06-11', '273'),
(576, '8428618532637222', '2027-05-28', '744'),
(576, '6923956680535368', '2028-03-31', '471'),
(577, '9638545965124611', '2030-01-14', '939'),
(577, '0938511916417132', '2029-06-01', '520'),
(577, '6833953755581680', '2030-01-06', '436'),
(578, '0482672828133799', '2028-02-27', '609'),
(579, '7415987753502457', '2028-09-15', '156'),
(579, '8106254360091205', '2027-08-19', '422'),
(580, '9183106089273596', '2028-04-03', '587'),
(581, '2838141709408212', '2027-07-14', '809'),
(581, '9046484808691867', '2028-11-23', '735'),
(582, '1751854962812447', '2029-04-10', '655'),
(583, '6256980176680079', '2028-07-24', '813'),
(583, '0692729115919899', '2028-02-16', '562'),
(584, '9861362205647160', '2028-07-20', '420'),
(585, '7387403805550799', '2030-01-15', '666'),
(586, '8616237681385413', '2027-08-31', '895'),
(586, '9413138541685216', '2027-09-27', '024'),
(586, '4308240293724213', '2028-08-27', '195'),
(587, '3262380414607884', '2028-04-10', '946'),
(587, '5293650998038341', '2029-06-18', '846'),
(588, '1383839307447705', '2027-06-25', '557'),
(589, '2105676516742777', '2027-11-23', '062'),
(589, '6104577724930792', '2029-05-27', '054'),
(590, '6081820734521780', '2029-09-29', '048'),
(591, '9621889448830098', '2028-01-23', '208'),
(591, '8067659603045899', '2028-08-17', '745'),
(592, '1716327593840247', '2027-06-05', '886'),
(593, '1775510109523947', '2028-07-07', '412'),
(594, '3737380028918566', '2027-10-17', '891'),
(594, '9678237655248116', '2029-10-16', '157'),
(594, '6845570654766835', '2028-05-07', '608'),
(595, '3242442493981424', '2029-05-10', '361'),
(595, '9242477158794065', '2029-06-25', '001'),
(596, '7316619067630384', '2028-02-26', '516'),
(597, '9650736201607954', '2028-08-21', '662'),
(598, '1395195236490931', '2028-04-08', '341'),
(598, '6414371347067352', '2029-03-11', '681'),
(599, '9465590209032874', '2028-10-05', '673'),
(599, '3839827513490221', '2029-11-23', '187'),
(600, '1546380482513118', '2028-10-20', '566'),
(600, '9051876277986111', '2028-09-16', '986'),
(601, '5981348387126845', '2028-07-10', '554'),
(601, '5442162038433324', '2027-09-06', '194'),
(601, '4978874039680199', '2029-03-31', '407'),
(602, '2200765544691576', '2029-07-30', '643'),
(603, '0325953950140573', '2028-11-28', '224'),
(603, '9723659993210703', '2028-10-22', '609'),
(603, '5952341743473683', '2029-08-03', '739'),
(604, '4801508993399669', '2028-08-30', '095'),
(604, '6017726633272747', '2028-10-10', '780'),
(604, '5508339703246649', '2028-02-15', '781'),
(605, '1696773708259724', '2028-07-25', '607'),
(605, '2279310354589508', '2028-03-18', '047'),
(606, '5768247855524902', '2029-12-30', '729'),
(606, '8607327018523960', '2029-12-17', '637'),
(607, '5384159555849561', '2027-07-22', '892'),
(608, '7906630494528385', '2030-02-11', '225'),
(608, '5032972637361935', '2028-11-16', '783'),
(608, '0779831653897414', '2029-11-19', '688'),
(609, '8785125796228652', '2028-12-06', '722'),
(609, '2005383307620614', '2027-06-19', '290'),
(610, '5682392279008691', '2028-04-09', '202'),
(611, '2096822635907281', '2028-07-29', '594'),
(611, '4949307968554629', '2029-01-02', '114'),
(612, '3790677714510385', '2029-02-22', '749'),
(612, '2572807989229172', '2029-09-20', '708'),
(612, '3854542156554154', '2028-04-18', '013'),
(613, '5998865666864827', '2029-11-17', '210'),
(614, '2227533622098855', '2027-04-05', '686'),
(615, '1571177609042665', '2029-09-28', '534'),
(616, '4604256942030399', '2029-11-26', '106'),
(616, '9385001576190110', '2029-01-10', '913'),
(616, '1999226495490806', '2029-11-29', '405'),
(617, '4778025547438146', '2029-08-14', '983'),
(617, '3707994725365019', '2028-02-04', '613'),
(618, '4044146372301152', '2028-01-09', '381'),
(618, '1769002784860228', '2028-01-04', '452'),
(619, '5673671867348441', '2029-02-25', '205'),
(619, '5708517219424234', '2028-03-01', '906'),
(619, '1241813711445250', '2028-04-19', '670'),
(620, '3379559148848149', '2027-12-27', '735'),
(621, '4994406709720199', '2028-12-26', '101'),
(621, '1544302905223889', '2027-12-26', '849'),
(621, '8558682196579443', '2029-08-08', '429'),
(622, '7935149388201387', '2029-01-29', '202'),
(622, '2055608220726058', '2029-05-14', '503'),
(623, '4351214933455264', '2029-12-09', '856'),
(623, '5869829885379083', '2029-06-10', '430'),
(624, '4138218587693334', '2027-07-31', '052'),
(624, '3781523547500542', '2027-04-12', '206'),
(624, '1807774622811295', '2027-08-02', '400'),
(625, '7848847254155217', '2028-06-25', '851'),
(626, '7477365532941123', '2027-11-15', '594'),
(626, '8118524441677022', '2028-02-02', '444'),
(627, '3472310257508925', '2028-08-15', '281'),
(628, '1369110928160470', '2027-10-18', '167'),
(629, '0868798087931385', '2028-09-29', '368'),
(629, '5708541801788609', '2027-06-24', '662'),
(630, '6161994453885854', '2029-01-17', '297'),
(630, '9314313656147746', '2028-01-09', '287'),
(631, '2954667556045478', '2028-09-17', '072'),
(631, '4997763169384933', '2027-08-01', '138'),
(632, '8407415824380307', '2027-09-22', '715'),
(632, '7140404452741273', '2028-06-19', '807'),
(633, '4132375480981054', '2028-08-08', '314'),
(634, '5559937685645242', '2028-04-15', '863'),
(634, '7883892854894510', '2028-05-18', '019'),
(634, '6075187123676728', '2028-04-26', '178'),
(635, '8910689217578275', '2027-05-11', '025'),
(635, '7404861231175105', '2029-06-23', '888'),
(635, '9546062093308169', '2029-06-11', '297'),
(636, '6209917564117235', '2029-12-19', '450'),
(636, '6656391461479269', '2028-12-24', '023'),
(636, '2379103842421415', '2028-07-27', '719'),
(637, '4542430178038997', '2028-06-15', '824'),
(637, '8596840644522492', '2028-05-22', '150'),
(637, '1495578613036147', '2027-09-23', '532'),
(638, '9047609627603026', '2027-02-26', '073'),
(639, '6152715832782537', '2028-04-10', '964'),
(639, '6178685393892277', '2027-12-12', '720'),
(639, '7551871922596937', '2028-02-22', '734'),
(640, '1692356076563811', '2028-08-02', '587'),
(641, '2224787162015678', '2029-06-20', '638'),
(642, '2485257635627689', '2029-12-14', '821'),
(643, '4456909412315822', '2028-12-18', '286'),
(643, '6274616435946301', '2027-04-28', '232'),
(644, '5765646923107945', '2028-06-09', '940'),
(644, '4943304494983217', '2029-05-25', '605'),
(644, '2658407034604033', '2030-01-27', '021'),
(645, '8737116975781277', '2027-08-23', '718'),
(645, '4696574851732952', '2029-10-21', '934'),
(646, '4496405984044367', '2028-09-30', '958'),
(646, '6919181499714636', '2028-08-22', '239'),
(646, '9533896576116949', '2027-12-03', '665'),
(647, '5871781047184609', '2030-02-04', '451'),
(647, '3236917098702778', '2029-03-05', '877'),
(648, '8038439478279178', '2029-09-15', '675'),
(648, '3992922518953828', '2028-10-06', '677'),
(648, '4089740806820343', '2028-04-29', '845'),
(649, '0872222461856747', '2030-01-09', '443'),
(649, '8396495348850076', '2027-08-23', '174'),
(649, '7716616396393768', '2029-07-07', '853'),
(650, '8512611844043431', '2027-07-31', '310'),
(650, '8853766431413727', '2027-05-26', '105'),
(651, '9514806194176709', '2028-07-06', '655'),
(651, '3715585785190348', '2029-05-10', '561'),
(651, '0509366904671013', '2027-08-17', '841'),
(652, '3126036673118845', '2029-12-05', '377'),
(652, '6402125610737953', '2029-11-11', '286'),
(652, '8629848837143715', '2028-02-15', '501'),
(653, '5893193290332103', '2028-09-01', '812'),
(653, '9674047133214303', '2029-10-26', '730'),
(653, '2819099361638493', '2027-05-19', '949'),
(654, '2631807285414369', '2027-06-15', '853'),
(655, '3592745501512129', '2028-01-19', '219'),
(655, '9955433097321977', '2029-07-12', '156'),
(656, '0677527903790534', '2028-10-06', '277'),
(656, '7097084645091006', '2030-01-26', '833'),
(657, '3566322236231041', '2027-06-17', '646'),
(657, '4071563828847673', '2029-12-12', '425'),
(658, '5307265879790012', '2028-11-03', '357'),
(658, '0247039382635752', '2028-09-01', '000'),
(658, '6059864715699441', '2028-01-17', '757'),
(659, '9366811807104927', '2028-11-29', '081'),
(660, '7086914804368824', '2027-08-28', '027'),
(660, '9319586672736658', '2028-11-10', '685'),
(661, '6401214715669599', '2028-07-22', '484'),
(661, '1677199891883518', '2028-12-17', '652'),
(661, '7104104809927999', '2028-02-11', '650'),
(662, '4060545751368537', '2027-11-08', '111'),
(663, '1599282752287367', '2028-04-16', '409'),
(663, '8894498361228540', '2028-03-22', '468'),
(664, '9738305193140880', '2029-11-22', '846'),
(664, '6352300247486203', '2028-06-29', '998'),
(665, '8556569318494424', '2029-11-16', '909'),
(666, '5238850737386963', '2029-03-29', '528'),
(666, '0919666366254658', '2027-11-04', '380'),
(667, '3898368005398852', '2030-01-04', '273'),
(667, '9216689748582352', '2029-04-20', '795'),
(667, '3635824838564775', '2028-03-20', '528'),
(668, '8081912781575979', '2029-06-25', '522'),
(668, '0638647279415576', '2028-11-12', '564'),
(669, '6302132519090049', '2028-02-11', '958'),
(669, '0759454937045201', '2029-06-10', '532'),
(669, '6595071972875715', '2028-09-26', '792'),
(670, '0500711386941427', '2027-07-29', '845'),
(670, '4498304501252632', '2028-08-15', '280'),
(670, '3980883072440734', '2029-02-11', '465'),
(671, '8524385413450843', '2027-09-10', '430'),
(671, '3325444657885226', '2028-11-22', '811'),
(671, '9760235061190464', '2027-09-08', '908'),
(672, '1470850028544296', '2029-10-17', '897'),
(672, '3328085638350583', '2029-04-16', '791'),
(673, '0231199912411413', '2028-07-06', '387'),
(674, '3959694417162593', '2027-05-01', '293'),
(674, '6611492791515859', '2028-08-15', '466'),
(674, '2487975419760792', '2028-08-19', '833'),
(675, '4995239516734587', '2028-06-27', '752'),
(676, '9434416797759396', '2029-12-05', '120'),
(676, '2324486261609572', '2028-01-31', '190'),
(676, '1288120492086176', '2029-04-25', '794'),
(677, '0364525864846824', '2029-04-02', '268'),
(678, '4226260098251222', '2027-07-13', '377'),
(678, '0016594046984697', '2029-10-22', '535'),
(678, '6906510657343783', '2029-08-13', '671'),
(679, '2558496173861669', '2029-08-30', '915'),
(679, '6339604837073702', '2029-04-03', '027'),
(680, '2874102340724102', '2027-12-21', '858'),
(680, '2160044737272841', '2027-06-09', '028'),
(681, '6446383856678733', '2027-02-24', '507'),
(682, '6645888240848361', '2027-06-01', '304'),
(682, '9739344010188955', '2027-12-23', '700'),
(683, '1974669307427802', '2027-04-18', '892'),
(683, '9326104276581295', '2027-12-13', '566'),
(684, '6222530425231965', '2029-08-17', '357'),
(684, '3704294647920986', '2027-12-07', '517'),
(685, '9538168380767408', '2027-11-23', '411'),
(686, '9728303560475207', '2029-08-03', '560'),
(686, '2131457720106493', '2029-02-10', '671'),
(687, '1793382176521377', '2029-10-13', '708'),
(687, '9353824975501145', '2027-09-04', '418'),
(687, '1217272645395729', '2028-02-15', '625'),
(688, '1827005260428192', '2027-07-22', '232'),
(688, '6529910940311575', '2029-03-02', '528'),
(689, '0596657633801452', '2029-03-24', '550'),
(689, '3790430929166931', '2027-11-15', '380'),
(690, '6774423032868061', '2028-05-15', '847'),
(690, '9183176564041224', '2028-01-16', '390'),
(690, '1522120215278560', '2028-02-20', '824'),
(691, '1741841546504565', '2027-02-25', '326'),
(692, '5986570980728327', '2028-01-01', '801'),
(692, '9916464102517468', '2028-01-18', '933'),
(692, '7735493528342913', '2029-12-09', '261'),
(693, '7830807136239500', '2027-08-29', '820'),
(694, '8312080773596755', '2028-01-14', '098'),
(694, '7246920455797627', '2028-04-23', '586'),
(695, '4999931400586637', '2029-06-28', '504'),
(695, '4453228078817602', '2027-06-22', '228'),
(695, '0101066767104202', '2030-02-09', '503'),
(696, '3256562319180086', '2027-12-28', '084'),
(697, '7198300759429957', '2027-04-20', '323'),
(698, '6881765365161798', '2029-10-29', '870'),
(698, '8085551537560653', '2028-06-22', '352'),
(699, '0800501715083589', '2029-08-12', '473'),
(699, '5051254692333740', '2028-04-01', '208'),
(700, '6400049265055256', '2029-12-06', '945'),
(701, '7304450128843577', '2028-08-29', '786'),
(701, '3963014325788706', '2029-05-22', '539'),
(701, '1282501771962818', '2027-08-06', '159'),
(702, '8597964777494621', '2027-03-05', '472'),
(702, '0384139246016671', '2029-06-20', '406'),
(703, '7527825893085981', '2028-02-17', '153'),
(703, '0773902211729547', '2028-04-10', '823'),
(703, '2100296832239766', '2028-07-19', '457'),
(704, '1684298328098743', '2027-08-14', '701'),
(704, '4527636233920091', '2027-04-27', '079'),
(704, '3523143634013779', '2029-06-01', '309'),
(705, '8326869000733053', '2029-11-07', '959'),
(705, '8070311358932502', '2028-07-27', '014'),
(705, '4435343415101061', '2028-02-10', '461'),
(706, '4042930162839848', '2029-09-21', '529'),
(706, '4254191242672747', '2029-11-14', '608'),
(707, '0533886438483759', '2027-03-17', '460'),
(708, '3478338019754751', '2028-03-14', '866'),
(708, '0958690067703396', '2028-10-29', '132'),
(708, '7006823952816232', '2029-05-24', '912'),
(709, '0011327455862466', '2028-10-01', '398'),
(710, '6928849673310560', '2028-05-15', '837'),
(710, '6584564713075175', '2027-03-08', '685'),
(711, '8832459563061515', '2030-01-15', '357'),
(711, '2019222626343985', '2029-04-28', '801'),
(712, '0239143880462505', '2027-04-29', '307'),
(712, '3702803790625660', '2027-04-21', '040'),
(712, '4329354629604965', '2029-03-31', '760'),
(713, '0593302806312312', '2029-06-28', '684'),
(713, '8777657416181759', '2028-03-15', '027'),
(713, '7936044385402207', '2027-11-26', '436'),
(714, '1957782294525114', '2028-09-09', '551'),
(714, '1772244494038523', '2029-08-20', '342'),
(715, '4074487741585183', '2027-06-08', '405'),
(716, '9506517836615337', '2029-12-21', '063'),
(716, '7306671128500002', '2028-08-31', '583'),
(716, '7224765830715480', '2027-04-06', '870'),
(717, '6670298665680454', '2027-12-23', '101'),
(718, '0610440085959270', '2028-11-15', '355'),
(719, '4999235444861316', '2030-02-01', '815'),
(719, '8057552536889602', '2029-02-26', '850'),
(720, '8363290978323218', '2027-04-22', '777'),
(720, '6586599783931444', '2028-01-27', '223'),
(721, '9788567030259225', '2027-07-29', '348'),
(721, '4558725614853305', '2027-09-21', '844'),
(721, '5905314339199969', '2030-01-20', '124'),
(722, '1669533464038212', '2028-10-12', '720'),
(723, '3491914666125870', '2028-05-30', '605'),
(723, '9329663375791189', '2029-05-05', '214'),
(724, '3173442721692917', '2029-12-03', '252'),
(724, '0041299898964977', '2028-11-08', '682'),
(724, '7307706472420194', '2030-01-29', '603'),
(725, '4483144973061565', '2028-01-24', '383'),
(725, '6029582947453139', '2027-02-26', '368'),
(726, '3842988843841139', '2027-08-15', '838'),
(726, '9361485550385385', '2028-06-25', '650'),
(726, '3050518415641222', '2027-06-01', '909'),
(727, '2509219328039388', '2027-12-31', '263'),
(727, '8792352059756904', '2027-11-26', '497'),
(728, '0978469897424232', '2029-02-18', '126'),
(729, '6037128119992484', '2029-01-08', '187'),
(729, '2474797504519546', '2027-11-01', '761'),
(730, '0667697036354277', '2029-11-26', '718'),
(730, '5441563721841463', '2027-12-10', '795'),
(731, '2275254034718334', '2027-08-19', '179'),
(731, '8854463898650784', '2030-02-19', '410'),
(731, '1793479877270519', '2028-12-11', '338'),
(732, '1036051128287118', '2028-10-02', '296'),
(733, '7463188749270533', '2027-08-09', '348'),
(734, '2815122431964566', '2028-07-09', '908'),
(734, '8583437512190882', '2029-08-21', '896'),
(735, '3763528457453618', '2029-04-13', '372'),
(735, '9366599080221321', '2027-03-17', '700'),
(735, '3270162656938174', '2029-03-31', '734'),
(736, '5830924648906432', '2028-10-20', '276'),
(736, '2259035007231105', '2028-12-15', '664'),
(737, '5539067901457157', '2027-06-24', '755'),
(738, '7937892104740817', '2028-04-24', '820'),
(738, '4355691998784520', '2029-08-28', '820'),
(738, '5916584047418411', '2027-07-26', '534'),
(739, '5152117597236461', '2027-10-31', '191'),
(739, '4482893851037413', '2027-11-03', '469'),
(739, '0101970210004740', '2027-03-23', '147'),
(740, '2877350965222970', '2027-11-01', '618'),
(740, '0245112770705031', '2028-10-06', '599'),
(741, '9406764317798536', '2028-04-20', '744'),
(742, '0384391443982065', '2027-06-04', '438'),
(742, '1526537268638067', '2029-08-23', '355'),
(743, '0110008829193408', '2029-02-25', '209'),
(743, '7040326587221740', '2028-01-22', '984'),
(744, '3308232641459006', '2028-05-22', '914'),
(745, '8966816739399712', '2030-01-28', '852'),
(746, '5012244333415035', '2027-05-07', '676'),
(747, '3035643305756833', '2029-03-09', '266'),
(748, '6606650541225575', '2028-02-08', '423'),
(749, '3266271780207902', '2027-11-20', '519'),
(749, '5343548692883238', '2027-11-19', '772'),
(749, '3042613711498701', '2029-08-03', '371'),
(750, '2172739469750645', '2027-03-02', '947'),
(750, '4241885008613216', '2028-08-06', '453'),
(751, '8057690940526552', '2029-07-18', '963'),
(752, '4647711844221899', '2027-09-26', '969'),
(753, '3595440815648216', '2028-04-24', '659'),
(754, '3072419666935536', '2028-01-25', '471'),
(754, '1867122317652359', '2027-07-23', '739'),
(754, '9419785193344089', '2029-02-18', '330'),
(755, '2939736118320491', '2028-12-05', '590'),
(755, '7176051078973692', '2029-01-13', '898'),
(755, '0327151925304666', '2028-09-24', '193'),
(756, '0530577545447663', '2029-03-27', '088'),
(757, '9595331859514100', '2029-08-13', '838'),
(757, '1740367180008469', '2028-08-23', '752'),
(757, '5533565577243424', '2028-08-01', '402'),
(758, '3151787097514878', '2029-02-11', '454'),
(758, '5151263812327896', '2028-05-23', '400'),
(758, '8989285077405688', '2027-04-11', '391'),
(759, '8238808721751405', '2027-02-27', '198'),
(759, '2789740907481673', '2027-05-08', '770'),
(760, '3405932083460868', '2028-12-06', '018'),
(761, '8099931152368394', '2029-02-18', '206'),
(761, '5695221129273514', '2027-09-06', '879'),
(761, '1574698324540636', '2027-11-16', '699'),
(762, '9898258488505440', '2027-11-04', '700'),
(763, '0365652663625007', '2027-06-06', '240'),
(764, '8265304550243909', '2028-06-11', '259'),
(764, '9272680369917081', '2027-06-17', '787'),
(765, '3128902682967858', '2027-05-05', '475'),
(765, '0168835279108612', '2029-12-31', '851'),
(766, '2317322708532590', '2028-01-31', '530'),
(767, '5791000136963913', '2029-04-21', '871'),
(768, '8128693954677861', '2030-01-21', '001'),
(768, '8692790436241439', '2028-08-11', '981'),
(769, '7221946194208655', '2030-01-18', '839'),
(769, '6347223709403375', '2029-11-22', '032'),
(770, '5899748677609064', '2027-06-16', '759'),
(770, '8736662518597251', '2030-02-15', '929'),
(770, '9285737928080085', '2028-02-27', '272'),
(771, '4014506867528355', '2028-08-14', '951'),
(771, '3894594060923787', '2028-11-27', '744'),
(772, '0287703789893358', '2028-05-07', '633'),
(773, '6075267170200175', '2028-03-16', '300'),
(774, '0743739908816387', '2029-07-18', '341'),
(774, '8623226832645355', '2029-05-14', '481'),
(775, '9319761644262988', '2029-09-21', '884'),
(775, '7604986174402611', '2028-05-04', '894'),
(776, '2372458263755593', '2027-12-16', '111'),
(777, '5433462304588040', '2027-12-17', '253'),
(778, '5553331841383536', '2027-10-31', '532'),
(778, '4644278286590081', '2029-08-23', '969'),
(779, '3117854934276776', '2029-11-20', '062'),
(779, '4922869022575191', '2029-10-10', '078'),
(779, '4288588979432637', '2029-12-10', '430'),
(780, '2191881102581068', '2028-07-17', '224'),
(781, '9260521005527554', '2027-08-15', '654'),
(781, '4236621202913331', '2027-09-25', '089'),
(782, '0201913312079512', '2027-07-21', '563'),
(782, '3358346713812976', '2029-08-12', '247'),
(783, '3427485272719715', '2029-11-22', '742'),
(783, '0756069484115541', '2027-09-28', '495'),
(784, '0722762656441018', '2028-04-30', '814'),
(784, '6688043592618273', '2028-09-12', '366'),
(784, '8498382917092643', '2028-01-06', '478'),
(785, '7683128708520907', '2027-08-11', '314'),
(785, '8315249657718026', '2028-04-07', '636'),
(786, '9978001718628635', '2027-10-17', '967'),
(787, '0043889907827389', '2027-06-23', '447'),
(787, '3757216146749248', '2027-11-21', '593'),
(788, '7682034473908488', '2027-02-23', '978'),
(788, '4714543330306286', '2028-11-16', '856'),
(789, '0061068797253784', '2029-01-11', '047'),
(789, '0437694064272235', '2027-08-16', '725'),
(789, '6334712085002061', '2029-05-02', '172'),
(790, '4097654393214384', '2029-03-08', '953'),
(790, '2997424910852735', '2027-07-09', '594'),
(790, '1379511981769286', '2027-07-11', '728'),
(791, '1366801037023081', '2029-02-17', '861'),
(792, '4497183654235697', '2028-09-07', '479'),
(792, '5739195502338896', '2029-12-04', '124'),
(792, '1022766848859092', '2027-05-17', '297'),
(793, '4037154523187548', '2028-01-28', '228'),
(793, '0621063921679398', '2029-03-07', '676'),
(794, '7902521985934791', '2028-04-23', '253'),
(794, '3212360660159438', '2028-02-28', '298'),
(794, '1657502217099959', '2030-01-25', '768'),
(795, '7759867844178718', '2029-04-28', '605'),
(795, '3997035423179431', '2029-04-25', '106'),
(796, '5516976329556826', '2028-10-20', '064'),
(796, '6268954021823630', '2027-11-28', '553'),
(796, '6120953507264180', '2027-11-10', '005'),
(797, '2534541363104221', '2027-03-21', '387'),
(797, '2269945804000426', '2027-05-31', '101'),
(798, '9476711900326525', '2028-03-16', '451'),
(798, '7869425277636109', '2028-12-18', '653'),
(799, '3805677851296988', '2027-04-18', '463'),
(799, '8046702529217914', '2028-08-15', '478'),
(799, '9687463857606519', '2027-09-17', '000'),
(800, '8358423954227690', '2027-08-06', '271'),
(800, '3322929777801144', '2030-01-30', '346'),
(800, '0847721701977468', '2028-05-07', '672'),
(801, '8964858469292029', '2028-03-28', '610'),
(801, '4364667121701698', '2029-02-04', '255'),
(802, '4715992135079182', '2028-11-18', '472'),
(803, '6482800368786585', '2028-01-02', '471'),
(804, '7617772982237665', '2029-01-19', '080'),
(804, '9695098477452806', '2029-06-13', '951'),
(804, '2455979347362069', '2029-07-04', '677'),
(805, '4340280873642007', '2028-11-18', '794'),
(805, '7364637345231073', '2027-11-16', '249'),
(805, '2610355473835900', '2029-03-08', '218'),
(806, '9884395198831929', '2027-08-13', '829'),
(806, '4500152312165461', '2027-07-30', '455'),
(807, '9851106340033206', '2027-12-25', '614'),
(808, '0482579209054814', '2028-07-02', '459'),
(808, '6711673237456628', '2029-12-24', '797'),
(808, '6406426095789748', '2029-04-16', '052'),
(809, '5901114645014786', '2027-06-19', '394'),
(810, '6765788528996012', '2027-12-30', '618'),
(810, '7802922149454571', '2029-11-30', '642'),
(811, '7081845813829178', '2027-10-20', '192'),
(812, '0907448027875724', '2028-04-06', '281'),
(812, '1427324956369009', '2029-08-23', '671'),
(812, '9761637377485697', '2029-03-18', '879'),
(813, '8069383130123829', '2029-10-14', '106'),
(813, '4665734482715494', '2028-07-05', '532'),
(813, '1218728896053493', '2029-09-10', '492'),
(814, '8187841676456857', '2027-05-20', '378'),
(815, '9777933709776243', '2028-11-02', '823'),
(815, '4349262782247555', '2027-10-09', '850'),
(816, '8297745728298873', '2027-04-07', '016'),
(816, '8570025346743643', '2027-05-21', '127'),
(817, '1308090009642194', '2029-06-17', '957'),
(817, '4061748036708055', '2029-08-13', '536'),
(817, '9101582548998599', '2028-05-11', '079'),
(818, '2428787133692658', '2027-07-20', '753'),
(819, '1136467933282416', '2027-10-01', '360'),
(819, '0535178290678410', '2027-06-20', '598'),
(819, '6059368038515757', '2028-02-15', '814'),
(820, '6443158442096533', '2028-05-02', '342'),
(820, '5303162839440728', '2029-06-08', '137'),
(821, '7976434692603006', '2028-10-24', '764'),
(821, '8825234273437083', '2029-05-08', '252'),
(821, '0557652629026836', '2029-02-27', '550'),
(822, '0737362511065973', '2028-01-29', '476'),
(822, '7164396254873964', '2027-10-02', '273'),
(822, '5252293110007111', '2027-04-22', '172'),
(823, '3964643616386844', '2027-09-19', '262'),
(824, '3058804752345529', '2027-05-05', '875'),
(824, '4978371816862987', '2028-07-08', '060'),
(825, '2772764627967100', '2027-07-18', '717'),
(826, '6001026668416831', '2027-04-23', '215'),
(826, '8940440518846033', '2029-07-05', '201'),
(827, '9840541205764946', '2029-06-03', '267'),
(828, '9065800638764182', '2027-05-26', '795'),
(828, '4215540336041979', '2029-04-06', '398'),
(828, '1471353780306919', '2027-10-16', '466'),
(829, '8500897388361303', '2027-03-09', '309'),
(830, '1244229558401845', '2029-01-26', '397'),
(831, '6808390997015395', '2028-09-20', '117'),
(832, '8980361599666802', '2027-08-09', '131'),
(833, '4254449764636833', '2029-07-18', '238'),
(833, '4232230474727724', '2029-01-23', '952'),
(833, '9977370444448527', '2028-08-12', '988'),
(834, '0894332014172784', '2029-08-17', '544'),
(834, '7560910110571505', '2030-01-14', '155'),
(835, '6543392897526051', '2029-02-22', '077'),
(835, '6346813720349945', '2027-04-30', '305'),
(835, '0133859463349049', '2029-07-06', '091'),
(836, '5921226513871098', '2030-02-21', '691'),
(836, '6782299900138984', '2027-11-02', '280'),
(837, '2856112242258759', '2027-10-13', '605'),
(838, '2316036784839811', '2029-04-11', '946'),
(838, '4650424562332418', '2029-10-20', '157'),
(839, '5506936455376298', '2029-03-22', '327'),
(839, '8352995207891480', '2028-12-05', '786'),
(839, '6672724931917287', '2028-06-04', '575'),
(840, '0140527699944746', '2029-03-27', '449'),
(840, '0639771621408406', '2028-03-24', '166'),
(841, '7774784537446023', '2027-09-08', '593'),
(841, '6827796142905032', '2029-07-05', '487'),
(842, '3445121421072016', '2029-10-03', '907'),
(843, '2867332717727819', '2027-07-07', '993'),
(844, '0712152541806458', '2027-07-02', '631'),
(845, '2803435482151210', '2029-12-27', '592'),
(846, '7691229951686621', '2027-06-12', '489'),
(847, '5852118163833201', '2028-05-17', '684'),
(848, '7568446118994007', '2028-08-28', '359'),
(849, '7469813455287930', '2029-05-05', '859'),
(850, '0774405524389862', '2028-10-25', '719'),
(850, '2179877370685296', '2029-01-25', '668'),
(851, '9308073466546916', '2027-04-15', '089'),
(851, '7211566431915625', '2028-05-07', '794'),
(851, '7998073582217470', '2030-01-03', '721'),
(852, '5681606352323687', '2027-10-31', '204'),
(853, '3790398427870433', '2027-07-03', '860'),
(853, '8012781850000078', '2028-08-16', '165'),
(853, '6188842355285578', '2027-11-23', '629'),
(854, '6556360737961355', '2028-05-07', '680'),
(855, '4921190206125245', '2028-08-06', '473'),
(855, '4165741109278231', '2029-01-02', '515'),
(856, '9545431609399638', '2029-08-29', '603'),
(856, '2589500956789038', '2029-03-25', '555'),
(857, '1983470421182425', '2027-04-13', '440'),
(857, '3877194243369614', '2028-11-19', '489'),
(858, '6441601318288388', '2029-01-31', '269'),
(859, '2338371706954644', '2029-05-29', '071'),
(859, '1940205338201788', '2028-04-28', '865'),
(860, '8921119067879201', '2028-01-03', '347'),
(860, '0021096465274305', '2029-09-27', '873'),
(861, '4286596722351855', '2027-06-16', '838'),
(861, '5277436009819519', '2028-07-05', '747'),
(862, '5677015591830672', '2028-08-26', '791'),
(863, '8812131473080220', '2027-05-11', '596'),
(864, '6778366167068171', '2029-07-25', '450'),
(865, '8663749198128377', '2029-03-23', '924'),
(865, '2028502334238391', '2029-02-04', '321'),
(866, '7049540231613982', '2029-02-20', '367'),
(866, '8714482222040552', '2030-02-15', '752'),
(867, '7110933437231308', '2028-10-14', '715'),
(867, '8376052633610089', '2029-12-11', '548'),
(867, '0321890984927095', '2029-07-17', '264'),
(868, '2919581269672137', '2030-01-27', '296'),
(868, '2647492588727836', '2028-07-30', '828'),
(868, '4237423389154948', '2029-08-06', '856'),
(869, '7157898552345223', '2029-09-09', '674'),
(869, '4960869118261174', '2028-08-28', '354'),
(870, '5508970011823502', '2029-12-26', '459'),
(870, '9172432995146858', '2029-03-01', '308'),
(871, '3112813690610456', '2028-08-20', '924'),
(871, '7019915578183002', '2029-06-08', '235'),
(871, '3308334331051359', '2028-03-23', '611'),
(872, '1618305465719500', '2027-03-09', '039'),
(872, '5087615681121272', '2028-12-27', '581'),
(872, '4930474856107890', '2028-05-09', '304'),
(873, '8292960626010979', '2029-11-23', '420'),
(873, '1990534729990702', '2028-11-15', '621'),
(874, '9225917137373004', '2029-01-22', '255'),
(874, '4017682578426365', '2028-08-03', '301'),
(874, '2413500510557605', '2027-11-09', '745'),
(875, '3303092701285170', '2027-05-21', '323'),
(875, '1847627686053356', '2028-07-01', '716'),
(876, '3092839238407470', '2027-05-09', '301'),
(876, '2434066237171276', '2029-08-11', '949'),
(876, '2132048200757092', '2027-10-31', '176'),
(877, '0140883159086260', '2028-08-04', '806'),
(877, '5490966401031218', '2027-04-22', '586'),
(877, '0611933226735313', '2028-06-28', '247'),
(878, '6131104865369097', '2028-01-12', '075'),
(878, '8564420413289929', '2028-02-01', '882'),
(879, '8892162960024180', '2029-02-15', '179'),
(879, '9919885589694213', '2028-03-29', '247'),
(879, '5140134316021162', '2030-01-02', '691'),
(880, '3079926983778961', '2028-11-28', '692'),
(880, '6958561472813594', '2028-08-02', '798'),
(881, '3133006430645647', '2027-08-26', '287'),
(881, '6866289048981565', '2027-04-29', '296'),
(881, '0426096158259967', '2029-02-05', '234'),
(882, '7929502667687044', '2028-08-25', '221'),
(882, '6970855248426579', '2028-06-09', '662'),
(882, '6960662870944732', '2027-05-15', '905'),
(883, '5033150422646604', '2028-09-16', '709'),
(883, '8916131453516137', '2027-11-02', '174'),
(884, '1925092633747371', '2029-11-08', '069'),
(884, '8385180320807450', '2027-06-28', '430'),
(884, '0139576485680750', '2029-01-21', '019'),
(885, '7505774762479335', '2029-04-30', '643'),
(886, '8365174616068831', '2030-01-07', '637'),
(887, '2085429461765849', '2027-06-16', '632'),
(887, '6951002144716292', '2029-01-05', '784'),
(887, '5263904870886189', '2029-09-18', '130'),
(888, '6499522615437195', '2028-02-03', '334'),
(888, '3823853079693497', '2028-09-21', '062'),
(888, '7110499870749311', '2027-04-22', '096'),
(889, '0512159861517058', '2028-10-21', '306'),
(889, '4934364427587551', '2027-05-13', '913'),
(889, '4738536070749635', '2028-03-26', '400'),
(890, '9694308843860008', '2029-03-08', '577'),
(890, '5202405455839106', '2028-12-17', '917'),
(891, '2149964386882098', '2029-01-30', '132'),
(892, '5507743251955253', '2027-11-13', '765'),
(893, '6992357547674334', '2029-03-14', '411'),
(893, '9119417048178658', '2030-01-15', '724'),
(894, '3547888937190405', '2028-03-10', '029'),
(894, '9376126865918377', '2027-09-20', '791'),
(895, '9834394040648136', '2027-05-31', '739'),
(895, '7725751137807442', '2027-08-23', '491'),
(895, '6648068714982838', '2027-12-10', '856'),
(896, '3391177430686025', '2030-01-09', '099'),
(897, '9271188367244850', '2028-02-09', '281'),
(897, '0667454715024707', '2029-08-19', '296'),
(898, '9929230508394005', '2028-07-27', '157'),
(899, '5105064393136256', '2028-12-14', '227'),
(900, '8816010715587452', '2027-08-10', '831'),
(900, '0084104138974626', '2028-08-26', '708'),
(900, '1148282664612468', '2027-09-26', '284'),
(901, '2005276372742487', '2028-07-07', '049'),
(902, '9979335256064682', '2029-07-10', '933'),
(902, '0479286757548558', '2028-09-21', '964'),
(903, '9882237628341900', '2028-01-11', '768'),
(903, '3214957800403630', '2028-06-28', '719'),
(903, '2111111818921993', '2029-10-26', '665'),
(904, '6822106219086671', '2029-10-15', '497'),
(904, '4782444076592822', '2028-06-09', '944'),
(905, '6529291498470731', '2028-12-05', '590'),
(905, '5327070194132884', '2028-07-15', '381'),
(906, '9326293707288556', '2028-04-05', '672'),
(907, '9082160179836462', '2027-11-28', '759'),
(908, '2110314017306121', '2028-09-14', '626'),
(908, '4861085205551567', '2028-08-20', '534'),
(908, '3015967053752164', '2027-04-18', '244'),
(909, '9467019929631052', '2029-06-15', '744'),
(909, '8383482097910220', '2027-12-20', '500'),
(910, '0210274670613800', '2029-06-29', '473'),
(910, '2473610534238120', '2029-01-16', '255'),
(911, '4897012838113220', '2027-09-20', '069'),
(911, '1540186372387036', '2029-07-23', '565'),
(912, '0092332358288177', '2027-08-09', '414'),
(912, '5679549062786283', '2028-05-25', '264'),
(913, '8013307791234969', '2029-06-24', '356'),
(914, '0371912371363715', '2027-10-09', '038'),
(914, '2181361867480070', '2029-06-24', '735'),
(915, '2010571569450263', '2027-06-21', '349'),
(915, '0936243880068284', '2028-08-23', '059'),
(916, '2183999715882252', '2028-10-14', '555'),
(916, '0067129629050499', '2029-07-30', '956'),
(917, '8978242770019925', '2030-02-19', '561'),
(917, '8397883963804858', '2028-04-25', '721'),
(917, '3408867762663902', '2029-05-03', '817'),
(918, '4449591024985734', '2029-09-02', '460'),
(918, '9145091330537237', '2027-08-23', '938'),
(919, '6193147760366112', '2028-03-09', '828'),
(919, '0152046251369550', '2027-12-06', '023'),
(920, '2980707384138353', '2029-06-15', '714'),
(920, '9801950131512878', '2027-07-05', '172'),
(920, '2779767314976849', '2027-06-05', '091'),
(921, '2948456068010566', '2027-12-10', '450'),
(921, '5761282550994818', '2029-09-11', '977'),
(922, '5961952175105518', '2027-04-05', '634'),
(922, '3527178229231407', '2028-04-28', '782'),
(922, '2983053560095318', '2029-10-11', '234'),
(923, '3013280780732853', '2029-09-05', '130'),
(923, '4721548394600536', '2028-10-25', '318'),
(923, '8538528055118505', '2027-09-09', '390'),
(924, '2535239712063889', '2030-02-22', '183'),
(924, '3754491408049021', '2030-01-16', '828'),
(924, '8304322292953668', '2027-05-12', '654'),
(925, '0075350586433124', '2028-10-08', '767'),
(925, '7986211977054103', '2029-10-19', '182'),
(925, '7029588743991290', '2027-07-25', '032'),
(926, '6056403476861597', '2027-09-20', '616'),
(926, '3757931296024938', '2028-02-08', '786'),
(927, '2060136033040762', '2028-09-26', '028'),
(928, '9170507289863881', '2027-11-09', '864'),
(928, '2936107679802409', '2028-04-27', '534'),
(928, '6038735499219178', '2027-03-30', '215'),
(929, '8938338404522031', '2027-06-25', '934'),
(929, '3587279962712723', '2028-01-21', '559'),
(929, '8650966941047944', '2029-02-20', '468'),
(930, '3395384688951362', '2028-11-06', '981'),
(930, '5725718342671514', '2029-10-10', '179'),
(931, '3704520661103728', '2027-05-14', '655'),
(931, '2114720077751967', '2028-03-24', '380'),
(932, '9890407793756306', '2027-09-12', '383'),
(932, '5462311369947039', '2028-05-05', '867'),
(932, '7503527974160229', '2028-04-11', '807'),
(933, '2253021341206578', '2028-05-26', '735'),
(933, '0607622442815027', '2028-05-03', '571'),
(934, '8579574696970944', '2030-02-08', '507'),
(934, '6022432949251353', '2029-12-16', '532'),
(934, '2789774369348922', '2029-03-08', '407'),
(935, '9480617277368774', '2028-04-02', '896'),
(935, '0687482464571657', '2027-10-21', '837'),
(935, '3980895457367286', '2028-03-14', '793'),
(936, '2603902017841026', '2030-01-19', '743'),
(937, '0945485098479970', '2029-03-12', '379'),
(937, '4273782159546927', '2027-03-06', '048'),
(937, '1994988018728510', '2029-03-12', '084'),
(938, '5510647126325470', '2028-06-12', '508'),
(938, '2981817019304169', '2028-01-20', '501'),
(939, '2640534514248103', '2028-09-25', '332'),
(940, '4332289276744611', '2027-07-07', '192'),
(941, '8928720460333986', '2029-10-21', '482'),
(941, '8512075405725047', '2028-05-11', '396'),
(942, '1769918444825910', '2027-03-22', '572'),
(942, '4475329828544758', '2028-05-16', '347'),
(943, '2599205071471410', '2027-07-09', '197'),
(944, '6423141938074301', '2027-11-09', '225'),
(945, '3543835284628224', '2028-06-26', '302'),
(945, '3946007320197863', '2028-07-06', '713'),
(946, '8234879182521184', '2028-11-30', '991'),
(946, '4701711140182448', '2028-07-11', '689'),
(946, '9806647032121089', '2029-01-04', '621'),
(947, '1667867163689845', '2028-08-13', '376'),
(947, '9967671888597600', '2029-06-30', '935'),
(948, '6099370762570782', '2027-05-06', '756'),
(948, '5820314929251836', '2027-10-01', '614'),
(949, '7858581201022982', '2028-04-21', '482'),
(950, '5242782306658642', '2030-01-07', '081'),
(950, '0617768902083428', '2029-06-15', '054'),
(951, '1808370414495932', '2027-03-07', '461'),
(951, '4567542711206336', '2029-12-22', '294'),
(952, '5231236544394739', '2029-04-30', '195'),
(952, '1846591859563702', '2029-11-01', '565'),
(952, '6042711848042673', '2027-05-08', '341'),
(953, '5913199879094725', '2027-06-20', '719'),
(953, '1467636949526436', '2030-01-25', '602'),
(953, '0681773408961619', '2028-08-11', '387'),
(954, '1656941804710237', '2027-12-13', '537'),
(954, '4640868984529291', '2027-10-18', '856'),
(954, '0177201662631040', '2028-11-09', '862'),
(955, '6239710742413302', '2028-01-26', '456'),
(956, '9649676046425912', '2029-04-18', '103'),
(957, '6955000752762081', '2029-11-17', '391'),
(958, '3082495135259744', '2029-05-15', '169'),
(959, '7146401390811412', '2029-07-16', '014'),
(959, '8883533168042219', '2029-12-13', '101'),
(959, '4268300627761248', '2028-07-31', '232'),
(960, '6865093929311637', '2029-09-04', '421'),
(960, '6617539326751416', '2029-06-06', '038'),
(961, '7556249179484034', '2028-04-12', '987'),
(962, '7695969793453103', '2027-10-27', '994'),
(962, '0578682742510977', '2029-07-24', '298'),
(963, '1774880943383299', '2028-05-23', '406'),
(964, '9233189097085080', '2027-04-16', '717'),
(964, '3336518562609696', '2028-10-27', '998'),
(965, '5970262995527441', '2027-03-25', '576'),
(965, '7115297307105200', '2029-08-11', '239'),
(965, '4056446843865413', '2029-02-16', '331'),
(966, '2092651816952953', '2029-01-04', '500'),
(966, '5917666897019932', '2030-01-06', '503'),
(967, '1996189593681949', '2029-04-23', '917'),
(967, '1710214624427078', '2028-08-14', '594'),
(967, '9929416492934008', '2029-06-26', '870'),
(968, '0420071924670262', '2029-11-15', '911'),
(968, '8092250900243384', '2028-12-24', '124'),
(968, '2515928862011924', '2027-12-05', '298'),
(969, '7329569519766991', '2030-01-10', '420'),
(970, '2639089288802533', '2027-09-19', '340'),
(970, '5919239185931551', '2028-10-27', '927'),
(970, '4155777899070199', '2027-12-18', '668'),
(971, '6164524218501101', '2029-04-05', '350'),
(972, '9787664295744564', '2028-10-25', '575'),
(972, '2143755657999640', '2027-10-29', '972'),
(972, '5586923548966996', '2028-03-13', '374'),
(973, '6267633431056672', '2028-10-03', '396'),
(974, '4028892179267538', '2028-01-16', '795'),
(975, '6529032655017335', '2027-06-02', '261'),
(975, '3683328875408146', '2028-05-24', '387'),
(976, '0750887154964779', '2028-05-02', '749'),
(977, '1227395547756714', '2029-01-05', '318'),
(977, '9037904704074806', '2027-10-23', '864'),
(978, '7762678446893847', '2027-09-14', '049'),
(979, '9925217489681623', '2029-11-09', '458'),
(979, '5220123887211288', '2028-07-06', '572'),
(980, '9326896366184528', '2027-04-08', '224'),
(980, '5715921998671903', '2027-06-01', '552'),
(980, '1982511091705647', '2029-08-02', '055'),
(981, '2423812923400676', '2029-07-24', '257'),
(981, '1717363008878925', '2027-11-08', '435'),
(981, '9460820526867133', '2028-10-12', '710'),
(982, '2258376335698318', '2028-03-19', '570'),
(983, '0309984609117168', '2029-10-02', '503'),
(983, '4111525657738644', '2029-12-03', '617'),
(983, '9425186968757001', '2027-07-07', '975'),
(984, '2387336175147176', '2028-02-03', '086'),
(984, '8098698682492806', '2029-11-28', '954'),
(985, '3119513616539293', '2028-02-06', '619'),
(986, '4211840424186967', '2029-11-26', '671'),
(986, '1493665522020542', '2028-08-18', '928'),
(987, '6374251388311290', '2029-08-12', '119'),
(988, '2993357873299591', '2029-02-19', '179'),
(989, '6126922350473963', '2029-01-31', '681'),
(989, '6744676103181614', '2027-07-21', '451'),
(989, '5612579206887361', '2027-12-31', '895'),
(990, '0328253550199561', '2027-03-05', '493'),
(990, '9821039922069384', '2028-09-04', '483'),
(990, '7267538050716403', '2028-09-01', '837'),
(991, '8510702948914790', '2028-06-13', '363'),
(991, '1052648797328301', '2028-07-14', '086'),
(992, '5534917391891873', '2028-12-30', '083'),
(993, '7522666495298029', '2028-06-09', '854'),
(993, '6796329029415132', '2029-04-10', '599'),
(994, '1294908641648583', '2028-02-25', '266'),
(994, '9819346193722522', '2028-06-15', '122'),
(995, '6462128830427152', '2030-01-29', '918'),
(995, '0589165461339879', '2028-12-27', '424'),
(996, '8327223967853872', '2029-03-09', '461'),
(996, '5539222439971098', '2027-06-14', '402'),
(996, '7545750740900778', '2029-12-18', '754'),
(997, '2160508319141086', '2029-03-31', '902'),
(997, '7904633000827633', '2027-06-07', '860'),
(998, '3366921661812640', '2029-10-17', '942'),
(998, '5203806040939517', '2027-10-05', '802'),
(999, '8132309988038249', '2029-05-30', '865'),
(999, '9315152783572536', '2029-05-21', '044'),
(1000, '7030064684963914', '2028-02-19', '798'),
(1000, '6891994276125233', '2027-06-15', '488');

/*transakcje*/INSERT INTO transakcje (id_konta, kwota, data_transakcji, typ) VALUES
(791, 186.69, '2023-06-05 18:03:50', 'wpłata'),
(665, 3464.63, '2025-01-29 18:03:50', 'wpłata'),
(849, 3459.5, '2024-11-17 18:03:50', 'wypłata'),
(749, 1072.37, '2023-08-06 18:03:50', 'wypłata'),
(342, 3825.43, '2024-07-21 18:03:50', 'wpłata'),
(649, 642.05, '2024-05-04 18:03:50', 'wypłata'),
(460, 2073.51, '2023-09-18 18:03:50', 'wypłata'),
(872, 712.34, '2024-06-26 18:03:50', 'wpłata'),
(165, 3312.85, '2023-09-23 18:03:50', 'wypłata'),
(962, 3457.42, '2024-08-18 18:03:50', 'wpłata'),
(986, 362.02, '2024-01-19 18:03:50', 'wypłata'),
(449, 1470.01, '2023-08-18 18:03:50', 'wypłata'),
(626, 610.91, '2024-02-05 18:03:50', 'wypłata'),
(153, 423.47, '2024-06-16 18:03:50', 'wpłata'),
(732, 2355.34, '2023-05-23 18:03:50', 'wpłata'),
(245, 1419.59, '2024-06-25 18:03:50', 'wpłata'),
(146, 3642.8, '2024-04-02 18:03:50', 'wpłata'),
(826, 2033.45, '2024-05-12 18:03:50', 'wpłata'),
(762, 4748.61, '2023-05-03 18:03:50', 'wpłata'),
(841, 4221.09, '2023-05-23 18:03:50', 'wpłata'),
(620, 3293.98, '2023-11-28 18:03:50', 'wpłata'),
(196, 2174.94, '2024-01-04 18:03:50', 'wypłata'),
(325, 2276.93, '2024-03-17 18:03:50', 'wypłata'),
(399, 2560.7, '2024-12-10 18:03:50', 'wpłata'),
(182, 4100.48, '2024-04-25 18:03:50', 'wpłata'),
(381, 911.79, '2024-02-20 18:03:50', 'wypłata'),
(289, 3528.96, '2023-04-11 18:03:50', 'wypłata'),
(338, 3764.62, '2023-12-22 18:03:50', 'wypłata'),
(702, 3305.47, '2024-10-26 18:03:50', 'wypłata'),
(156, 2987.96, '2024-03-24 18:03:50', 'wpłata'),
(222, 4777.26, '2025-02-16 18:03:50', 'wpłata'),
(663, 1339.58, '2023-10-09 18:03:50', 'wpłata'),
(412, 4062.38, '2023-09-23 18:03:50', 'wpłata'),
(450, 2268.75, '2023-06-28 18:03:50', 'wpłata'),
(984, 3430.9, '2023-10-08 18:03:50', 'wypłata'),
(437, 3883.13, '2024-05-17 18:03:50', 'wpłata'),
(554, 2744.77, '2023-05-11 18:03:50', 'wypłata'),
(163, 3476.55, '2024-06-17 18:03:50', 'wpłata'),
(365, 4847.78, '2023-09-28 18:03:50', 'wypłata'),
(505, 956.55, '2024-03-08 18:03:50', 'wypłata'),
(191, 3344.54, '2024-11-28 18:03:50', 'wpłata'),
(663, 2661.68, '2023-11-14 18:03:50', 'wypłata'),
(491, 1660.92, '2023-03-06 18:03:50', 'wypłata'),
(912, 4242.8, '2024-12-08 18:03:50', 'wypłata'),
(407, 3602.95, '2024-12-26 18:03:50', 'wpłata'),
(481, 3072.14, '2024-08-30 18:03:50', 'wpłata'),
(882, 4945.49, '2024-09-28 18:03:50', 'wypłata'),
(115, 480.8, '2024-07-30 18:03:50', 'wpłata'),
(67, 2710.03, '2023-10-27 18:03:50', 'wypłata'),
(175, 2581.88, '2023-09-29 18:03:50', 'wpłata'),
(243, 1953.95, '2023-09-26 18:03:50', 'wypłata'),
(589, 4219.19, '2024-05-08 18:03:50', 'wpłata'),
(160, 827.03, '2023-09-09 18:03:50', 'wpłata'),
(530, 4721.16, '2024-05-17 18:03:50', 'wpłata'),
(110, 4251.19, '2024-09-13 18:03:50', 'wypłata'),
(396, 1807.88, '2024-05-18 18:03:50', 'wypłata'),
(772, 311.25, '2023-07-31 18:03:50', 'wypłata'),
(918, 3161.99, '2023-07-07 18:03:50', 'wypłata'),
(842, 4402.12, '2023-06-17 18:03:50', 'wypłata'),
(533, 4102.83, '2024-04-09 18:03:50', 'wpłata'),
(692, 2761.74, '2023-12-12 18:03:50', 'wpłata'),
(378, 3094.17, '2024-06-12 18:03:50', 'wpłata'),
(117, 3940.82, '2023-12-03 18:03:50', 'wpłata'),
(414, 4356.23, '2023-12-29 18:03:50', 'wypłata'),
(437, 250.6, '2024-06-27 18:03:50', 'wypłata'),
(922, 3855.65, '2023-12-21 18:03:50', 'wpłata'),
(370, 3743.04, '2023-06-01 18:03:50', 'wypłata'),
(790, 3927.69, '2024-01-03 18:03:50', 'wypłata'),
(680, 1066.96, '2023-06-24 18:03:50', 'wpłata'),
(216, 2013.76, '2024-11-23 18:03:50', 'wpłata'),
(534, 770.89, '2023-04-09 18:03:50', 'wpłata'),
(946, 2809.79, '2023-07-17 18:03:50', 'wypłata'),
(987, 2690.19, '2025-01-27 18:03:50', 'wypłata'),
(833, 4534.75, '2023-12-23 18:03:50', 'wpłata'),
(76, 3102.7, '2024-08-17 18:03:50', 'wypłata'),
(686, 1912.06, '2024-01-02 18:03:50', 'wypłata'),
(311, 2740.6, '2024-08-15 18:03:50', 'wypłata'),
(143, 2777.16, '2024-08-05 18:03:50', 'wypłata'),
(702, 672.88, '2023-12-05 18:03:50', 'wpłata'),
(821, 3314.43, '2024-01-15 18:03:50', 'wypłata'),
(988, 2603.48, '2023-05-29 18:03:50', 'wpłata'),
(532, 4825.97, '2024-10-19 18:03:50', 'wypłata'),
(809, 3773.97, '2024-03-14 18:03:50', 'wpłata'),
(639, 1073.61, '2024-12-19 18:03:50', 'wypłata'),
(285, 3748.83, '2023-08-07 18:03:50', 'wpłata'),
(168, 2025.42, '2023-09-06 18:03:50', 'wypłata'),
(32, 804.99, '2024-11-24 18:03:50', 'wypłata'),
(109, 1758.97, '2024-12-12 18:03:50', 'wypłata'),
(783, 3900.45, '2024-12-13 18:03:50', 'wypłata'),
(543, 1309.62, '2023-07-25 18:03:50', 'wpłata'),
(699, 2973.5, '2025-02-03 18:03:50', 'wpłata'),
(847, 2242.48, '2024-03-03 18:03:50', 'wypłata'),
(19, 3608.68, '2025-01-19 18:03:50', 'wpłata'),
(991, 3932.96, '2023-10-09 18:03:50', 'wpłata'),
(255, 3120.22, '2023-09-09 18:03:50', 'wpłata'),
(895, 2649.11, '2024-05-16 18:03:50', 'wypłata'),
(888, 3285.8, '2023-06-11 18:03:50', 'wpłata'),
(778, 2250.88, '2024-12-09 18:03:50', 'wypłata'),
(192, 2911.9, '2023-04-28 18:03:50', 'wpłata'),
(946, 2062.37, '2023-12-22 18:03:50', 'wypłata'),
(28, 2251.45, '2024-01-27 18:03:50', 'wpłata'),
(664, 3919.82, '2025-01-22 18:03:50', 'wypłata'),
(120, 1689.46, '2024-05-20 18:03:50', 'wypłata'),
(392, 2265.26, '2024-01-05 18:03:50', 'wypłata'),
(165, 1980.29, '2025-01-06 18:03:50', 'wpłata'),
(757, 3073.41, '2024-06-06 18:03:50', 'wypłata'),
(550, 3822.98, '2023-05-03 18:03:50', 'wypłata'),
(345, 2393.26, '2023-04-13 18:03:50', 'wpłata'),
(435, 4517.76, '2023-05-12 18:03:50', 'wypłata'),
(748, 1969.37, '2023-06-13 18:03:50', 'wpłata'),
(199, 4755.33, '2023-05-08 18:03:50', 'wypłata'),
(726, 3572.18, '2023-07-26 18:03:50', 'wypłata'),
(254, 293.57, '2023-08-30 18:03:50', 'wypłata'),
(187, 3039.07, '2023-07-15 18:03:50', 'wpłata'),
(622, 1899.3, '2023-11-14 18:03:50', 'wpłata'),
(973, 2601.49, '2024-07-29 18:03:50', 'wpłata'),
(614, 3326.03, '2024-01-31 18:03:50', 'wpłata'),
(277, 2044.24, '2024-03-05 18:03:50', 'wypłata'),
(18, 3356.63, '2024-01-30 18:03:50', 'wpłata'),
(428, 4563.9, '2023-10-03 18:03:50', 'wpłata'),
(335, 3716.64, '2024-04-18 18:03:50', 'wypłata'),
(46, 1774.99, '2023-07-25 18:03:50', 'wypłata'),
(795, 4233.84, '2024-06-15 18:03:50', 'wypłata'),
(805, 2536.53, '2024-09-19 18:03:50', 'wypłata'),
(365, 4568.87, '2023-05-24 18:03:50', 'wpłata'),
(503, 56.02, '2024-02-19 18:03:50', 'wypłata'),
(886, 87.45, '2023-09-10 18:03:50', 'wpłata'),
(219, 1447.78, '2024-08-23 18:03:50', 'wypłata'),
(636, 1879.94, '2023-07-18 18:03:50', 'wypłata'),
(543, 1114.48, '2023-10-28 18:03:50', 'wypłata'),
(785, 1168.55, '2025-01-19 18:03:50', 'wpłata'),
(315, 2857.09, '2024-02-19 18:03:50', 'wpłata'),
(438, 1356.32, '2025-02-09 18:03:50', 'wpłata'),
(681, 498.72, '2023-10-24 18:03:50', 'wypłata'),
(331, 1443.87, '2024-11-22 18:03:50', 'wypłata'),
(543, 1267.79, '2023-11-30 18:03:50', 'wypłata'),
(837, 277.66, '2024-08-10 18:03:50', 'wypłata'),
(632, 27.01, '2023-06-14 18:03:50', 'wypłata'),
(97, 2637.46, '2023-06-21 18:03:50', 'wypłata'),
(682, 4590.42, '2024-05-14 18:03:50', 'wpłata'),
(211, 3101.05, '2025-01-27 18:03:50', 'wypłata'),
(769, 3931.64, '2023-03-14 18:03:50', 'wpłata'),
(965, 2647.53, '2024-06-12 18:03:50', 'wypłata'),
(537, 3736.8, '2024-07-26 18:03:50', 'wypłata'),
(307, 3565.68, '2024-03-05 18:03:50', 'wypłata'),
(72, 3538.67, '2024-01-19 18:03:50', 'wpłata'),
(727, 3131.45, '2023-08-06 18:03:50', 'wpłata'),
(881, 958.05, '2023-05-18 18:03:50', 'wypłata'),
(118, 861.82, '2024-12-16 18:03:50', 'wypłata'),
(663, 3292.79, '2024-07-28 18:03:50', 'wypłata'),
(482, 4201.84, '2023-12-17 18:03:50', 'wypłata'),
(787, 1080.57, '2024-09-23 18:03:50', 'wypłata'),
(118, 357.2, '2025-01-06 18:03:50', 'wpłata'),
(868, 4322.21, '2024-03-31 18:03:50', 'wypłata'),
(60, 2337.31, '2025-02-07 18:03:50', 'wpłata'),
(957, 4664.87, '2024-09-19 18:03:50', 'wpłata'),
(595, 224.44, '2023-07-19 18:03:50', 'wpłata'),
(968, 2121.69, '2024-11-23 18:03:50', 'wpłata'),
(913, 341.62, '2024-05-28 18:03:50', 'wpłata'),
(491, 1116.62, '2024-12-07 18:03:50', 'wypłata'),
(586, 4190.53, '2024-09-26 18:03:50', 'wpłata'),
(126, 2635.64, '2024-11-10 18:03:50', 'wypłata'),
(403, 1759.66, '2024-10-21 18:03:50', 'wpłata'),
(499, 3433.68, '2024-07-29 18:03:50', 'wpłata'),
(265, 2139.9, '2025-02-03 18:03:50', 'wpłata'),
(119, 4515.2, '2024-02-09 18:03:50', 'wpłata'),
(444, 4789.94, '2024-07-16 18:03:50', 'wpłata'),
(284, 2207.22, '2023-09-06 18:03:50', 'wypłata'),
(635, 1386.12, '2023-03-24 18:03:50', 'wypłata'),
(770, 1323.73, '2024-01-07 18:03:50', 'wpłata'),
(876, 1568.9, '2024-03-17 18:03:50', 'wpłata'),
(479, 1009.48, '2024-02-28 18:03:50', 'wypłata'),
(930, 1849.5, '2024-02-01 18:03:50', 'wpłata'),
(712, 4516.26, '2024-08-19 18:03:50', 'wpłata'),
(49, 4953.89, '2024-02-19 18:03:50', 'wpłata'),
(588, 34.98, '2023-08-28 18:03:50', 'wpłata'),
(446, 1841.78, '2023-12-07 18:03:50', 'wypłata'),
(543, 2020.17, '2023-07-13 18:03:50', 'wpłata'),
(461, 3798.13, '2023-10-08 18:03:50', 'wpłata'),
(385, 1554.6, '2023-09-20 18:03:50', 'wypłata'),
(294, 1341.97, '2024-10-21 18:03:50', 'wpłata'),
(343, 1824.17, '2023-08-25 18:03:50', 'wypłata'),
(559, 1721.77, '2023-08-19 18:03:50', 'wpłata'),
(855, 1000.07, '2024-09-01 18:03:50', 'wpłata'),
(795, 1787.86, '2024-04-30 18:03:50', 'wypłata'),
(584, 652.53, '2023-11-21 18:03:50', 'wypłata'),
(771, 2514.25, '2023-10-28 18:03:50', 'wypłata'),
(459, 1815.65, '2024-09-16 18:03:50', 'wypłata'),
(435, 3299.05, '2023-03-13 18:03:50', 'wypłata'),
(869, 4919.75, '2024-03-20 18:03:50', 'wypłata'),
(967, 4942.14, '2024-02-01 18:03:50', 'wypłata'),
(45, 4655.51, '2024-08-22 18:03:50', 'wpłata'),
(769, 4468.98, '2023-06-11 18:03:50', 'wpłata'),
(592, 3319.24, '2024-10-14 18:03:50', 'wpłata'),
(853, 2247.6, '2025-02-27 18:03:50', 'wpłata'),
(412, 3974.1, '2024-03-01 18:03:50', 'wpłata'),
(739, 4916.3, '2024-10-26 18:03:50', 'wpłata'),
(9, 425.41, '2023-10-27 18:03:50', 'wpłata'),
(246, 2401.91, '2024-01-16 18:03:50', 'wypłata'),
(479, 4571.6, '2024-10-02 18:03:50', 'wypłata'),
(930, 2046.02, '2023-10-06 18:03:50', 'wpłata'),
(753, 702.51, '2024-03-09 18:03:50', 'wpłata'),
(14, 3542.45, '2023-08-22 18:03:50', 'wypłata'),
(101, 1688.96, '2024-08-02 18:03:50', 'wypłata'),
(324, 165.68, '2023-09-11 18:03:50', 'wypłata'),
(570, 1504.35, '2025-01-08 18:03:50', 'wypłata'),
(536, 489.55, '2024-11-14 18:03:50', 'wypłata'),
(25, 674.52, '2023-12-25 18:03:50', 'wypłata'),
(968, 3473.43, '2023-03-27 18:03:50', 'wypłata'),
(849, 3155.87, '2025-01-05 18:03:50', 'wpłata'),
(846, 4904.38, '2024-02-25 18:03:50', 'wypłata'),
(103, 344.01, '2024-12-16 18:03:50', 'wpłata'),
(351, 4079.81, '2024-10-02 18:03:50', 'wypłata'),
(865, 375.09, '2023-09-20 18:03:50', 'wpłata'),
(139, 4017.32, '2023-12-12 18:03:50', 'wypłata'),
(433, 3305.17, '2024-09-11 18:03:50', 'wpłata'),
(177, 2038.01, '2023-05-14 18:03:50', 'wpłata'),
(995, 98.02, '2024-10-30 18:03:50', 'wpłata'),
(168, 4542.58, '2024-01-23 18:03:50', 'wpłata'),
(129, 786.54, '2024-11-15 18:03:50', 'wpłata'),
(211, 4643.77, '2023-12-05 18:03:50', 'wypłata'),
(143, 641.74, '2024-05-18 18:03:50', 'wypłata'),
(540, 3977.07, '2024-06-22 18:03:50', 'wypłata'),
(508, 3563.96, '2024-05-30 18:03:50', 'wypłata'),
(442, 3350.05, '2023-07-09 18:03:50', 'wpłata'),
(794, 2865.55, '2024-01-19 18:03:50', 'wpłata'),
(944, 2122.6, '2024-04-30 18:03:50', 'wpłata'),
(866, 2513.55, '2024-03-26 18:03:50', 'wpłata'),
(685, 1385.02, '2024-06-19 18:03:50', 'wypłata'),
(367, 3192.43, '2024-02-06 18:03:50', 'wpłata'),
(836, 2086.71, '2024-06-29 18:03:50', 'wypłata'),
(639, 1922.52, '2023-05-17 18:03:50', 'wypłata'),
(322, 2299.53, '2024-10-19 18:03:50', 'wpłata'),
(101, 4230.02, '2023-11-16 18:03:50', 'wypłata'),
(65, 1649.49, '2025-02-25 18:03:50', 'wpłata'),
(415, 4782.72, '2023-12-20 18:03:50', 'wypłata'),
(374, 1577.26, '2023-07-23 18:03:50', 'wypłata'),
(361, 1899.12, '2023-04-03 18:03:50', 'wypłata'),
(967, 1677.74, '2023-12-19 18:03:50', 'wypłata'),
(810, 1032.61, '2024-06-11 18:03:50', 'wpłata'),
(942, 4389.39, '2024-07-22 18:03:50', 'wpłata'),
(382, 3197.9, '2025-02-27 18:03:50', 'wpłata'),
(65, 2364.98, '2023-12-26 18:03:50', 'wpłata'),
(834, 3455.53, '2023-12-11 18:03:50', 'wpłata'),
(808, 675.01, '2024-07-07 18:03:50', 'wpłata'),
(732, 3673.19, '2025-02-01 18:03:50', 'wypłata'),
(79, 3256.38, '2024-03-29 18:03:50', 'wpłata'),
(585, 1227.48, '2023-03-14 18:03:50', 'wpłata'),
(563, 951.41, '2023-10-14 18:03:50', 'wypłata'),
(583, 4462.1, '2024-12-21 18:03:50', 'wpłata'),
(58, 587.94, '2025-01-18 18:03:50', 'wpłata'),
(522, 224.44, '2024-03-28 18:03:50', 'wypłata'),
(487, 2158.59, '2024-07-25 18:03:50', 'wypłata'),
(506, 3886.29, '2024-06-09 18:03:50', 'wpłata'),
(470, 3940.08, '2023-07-22 18:03:50', 'wpłata'),
(182, 4239.89, '2023-11-05 18:03:50', 'wpłata'),
(197, 2762.82, '2024-05-13 18:03:50', 'wpłata'),
(353, 2512.75, '2023-04-12 18:03:50', 'wpłata'),
(779, 3197.96, '2024-08-19 18:03:50', 'wypłata'),
(653, 2102.73, '2023-08-17 18:03:50', 'wypłata'),
(786, 1690.69, '2024-04-29 18:03:50', 'wpłata'),
(512, 1503.18, '2025-01-06 18:03:50', 'wypłata'),
(928, 704.12, '2024-07-28 18:03:50', 'wpłata'),
(958, 4706.76, '2024-10-22 18:03:50', 'wypłata'),
(347, 942.5, '2024-07-24 18:03:50', 'wpłata'),
(156, 2841.56, '2025-02-09 18:03:50', 'wpłata'),
(969, 53.54, '2023-09-16 18:03:50', 'wypłata'),
(24, 757.62, '2024-12-30 18:03:50', 'wypłata'),
(845, 1572.14, '2023-11-07 18:03:50', 'wypłata'),
(210, 495.9, '2024-11-06 18:03:50', 'wypłata'),
(978, 288.95, '2023-08-05 18:03:50', 'wpłata'),
(52, 4671.76, '2024-12-02 18:03:50', 'wypłata'),
(503, 4768.91, '2024-09-25 18:03:50', 'wypłata'),
(495, 970.62, '2024-08-27 18:03:50', 'wypłata'),
(788, 3109.88, '2023-03-15 18:03:50', 'wpłata'),
(207, 4917.09, '2024-01-09 18:03:50', 'wpłata'),
(425, 1026.43, '2023-06-27 18:03:50', 'wpłata'),
(459, 2839.48, '2024-04-13 18:03:50', 'wpłata'),
(40, 1647.63, '2023-10-26 18:03:50', 'wpłata'),
(731, 2556.39, '2024-07-24 18:03:50', 'wpłata'),
(181, 1402.48, '2023-03-09 18:03:50', 'wpłata'),
(914, 1262.3, '2023-12-16 18:03:50', 'wpłata'),
(336, 919.84, '2023-05-28 18:03:50', 'wpłata'),
(381, 3637.09, '2024-07-02 18:03:50', 'wypłata'),
(72, 1597.72, '2024-08-02 18:03:50', 'wpłata'),
(284, 2860.69, '2023-08-08 18:03:50', 'wypłata'),
(792, 3597.7, '2023-08-14 18:03:50', 'wpłata'),
(209, 463.81, '2024-06-18 18:03:50', 'wpłata'),
(738, 3276.09, '2024-08-31 18:03:50', 'wypłata'),
(166, 1030.44, '2024-01-16 18:03:50', 'wpłata'),
(60, 1136.33, '2025-02-06 18:03:50', 'wypłata'),
(747, 3461.67, '2024-08-25 18:03:50', 'wpłata'),
(128, 1466.87, '2024-11-13 18:03:50', 'wypłata'),
(674, 1201.08, '2024-08-14 18:03:50', 'wypłata'),
(695, 3984.76, '2023-12-13 18:03:50', 'wypłata'),
(889, 1808.48, '2024-10-05 18:03:50', 'wpłata'),
(594, 894.86, '2025-02-28 18:03:50', 'wpłata'),
(628, 3036.16, '2024-09-26 18:03:50', 'wypłata'),
(705, 1593.91, '2025-01-25 18:03:50', 'wypłata'),
(8, 77.47, '2024-08-28 18:03:50', 'wypłata'),
(84, 401.34, '2023-03-09 18:03:50', 'wypłata'),
(727, 861.34, '2023-09-06 18:03:50', 'wypłata'),
(485, 4960.65, '2023-04-23 18:03:50', 'wypłata'),
(777, 1079.77, '2024-08-27 18:03:50', 'wypłata'),
(269, 1947.04, '2024-10-13 18:03:50', 'wpłata'),
(543, 3693.34, '2023-09-17 18:03:50', 'wpłata'),
(708, 2788.88, '2025-01-21 18:03:50', 'wpłata'),
(733, 3820.2, '2025-02-24 18:03:50', 'wpłata'),
(198, 777.56, '2023-07-24 18:03:50', 'wpłata'),
(488, 1533.2, '2023-12-24 18:03:50', 'wypłata'),
(439, 1549.78, '2024-02-19 18:03:50', 'wypłata'),
(185, 1565.4, '2024-10-29 18:03:50', 'wypłata'),
(62, 400.48, '2023-10-31 18:03:50', 'wypłata'),
(166, 4891.92, '2024-11-14 18:03:50', 'wypłata'),
(948, 4466.16, '2025-01-15 18:03:50', 'wypłata'),
(725, 4803.67, '2023-09-06 18:03:50', 'wypłata'),
(325, 3662.52, '2023-05-23 18:03:50', 'wypłata'),
(276, 4979.17, '2023-09-22 18:03:50', 'wypłata'),
(151, 4303.66, '2024-07-10 18:03:50', 'wpłata'),
(238, 4386.7, '2024-01-05 18:03:50', 'wpłata'),
(690, 3424.7, '2023-11-11 18:03:50', 'wypłata'),
(383, 722.34, '2023-04-18 18:03:50', 'wpłata'),
(923, 1359.04, '2024-11-25 18:03:50', 'wypłata'),
(199, 246.55, '2024-08-08 18:03:50', 'wpłata'),
(629, 4235.29, '2023-04-27 18:03:50', 'wpłata'),
(210, 2986.37, '2024-09-06 18:03:50', 'wpłata'),
(211, 2059.81, '2024-06-08 18:03:50', 'wpłata'),
(83, 3426.61, '2023-04-21 18:03:50', 'wpłata'),
(419, 3998.42, '2024-09-21 18:03:50', 'wypłata'),
(481, 1439.4, '2023-04-22 18:03:50', 'wypłata'),
(475, 3503.92, '2024-07-25 18:03:50', 'wpłata'),
(882, 4989.22, '2024-02-01 18:03:50', 'wypłata'),
(265, 4866.43, '2024-05-31 18:03:50', 'wypłata'),
(409, 3945.02, '2023-12-23 18:03:50', 'wpłata'),
(311, 36.63, '2024-05-11 18:03:50', 'wypłata'),
(281, 2467.28, '2024-09-26 18:03:50', 'wypłata'),
(707, 3246.55, '2024-04-12 18:03:50', 'wypłata'),
(162, 59.93, '2025-01-02 18:03:50', 'wpłata'),
(166, 2002.43, '2024-11-12 18:03:50', 'wypłata'),
(1000, 3198.01, '2023-09-05 18:03:50', 'wypłata'),
(845, 3161.55, '2023-07-14 18:03:50', 'wypłata'),
(95, 3146.75, '2023-12-07 18:03:50', 'wypłata'),
(641, 135.64, '2024-01-13 18:03:50', 'wpłata'),
(379, 646.78, '2023-11-14 18:03:50', 'wypłata'),
(450, 2448.38, '2023-09-10 18:03:50', 'wpłata'),
(831, 1286.84, '2024-10-29 18:03:50', 'wypłata'),
(339, 3920.22, '2023-10-03 18:03:50', 'wypłata'),
(142, 1768.19, '2023-05-08 18:03:50', 'wypłata'),
(913, 4280.62, '2024-09-02 18:03:50', 'wypłata'),
(67, 1108.15, '2024-01-06 18:03:50', 'wypłata'),
(923, 2427.02, '2023-08-20 18:03:50', 'wpłata'),
(552, 243.49, '2024-12-07 18:03:50', 'wypłata'),
(968, 211.45, '2024-03-16 18:03:50', 'wpłata'),
(545, 800.94, '2023-03-27 18:03:50', 'wypłata'),
(808, 3324.74, '2023-09-01 18:03:50', 'wypłata'),
(600, 1688.71, '2023-06-30 18:03:50', 'wpłata'),
(584, 3240.84, '2023-12-16 18:03:50', 'wypłata'),
(851, 4397.22, '2023-05-08 18:03:50', 'wpłata'),
(667, 4798.4, '2025-01-06 18:03:50', 'wpłata'),
(168, 195.92, '2023-10-21 18:03:50', 'wypłata'),
(84, 4161.28, '2024-06-21 18:03:50', 'wpłata'),
(713, 2928.14, '2024-10-04 18:03:50', 'wpłata'),
(102, 1548.33, '2023-10-11 18:03:50', 'wpłata'),
(371, 2302.9, '2024-06-18 18:03:50', 'wypłata'),
(492, 1566.77, '2023-09-24 18:03:50', 'wypłata'),
(291, 4223.85, '2023-10-22 18:03:50', 'wypłata'),
(588, 526.47, '2023-10-01 18:03:50', 'wypłata'),
(4, 250.51, '2024-02-13 18:03:50', 'wpłata'),
(743, 2326.53, '2024-07-16 18:03:50', 'wpłata'),
(586, 4401.68, '2024-10-13 18:03:50', 'wypłata'),
(101, 2154.07, '2024-04-13 18:03:50', 'wypłata'),
(215, 1601.51, '2024-10-17 18:03:50', 'wpłata'),
(604, 121.47, '2025-02-24 18:03:50', 'wpłata'),
(41, 1110.8, '2024-10-22 18:03:50', 'wpłata'),
(351, 1931.45, '2024-01-18 18:03:50', 'wypłata'),
(642, 3499.36, '2025-02-16 18:03:50', 'wypłata'),
(346, 2728.76, '2024-11-02 18:03:50', 'wpłata'),
(318, 1327.12, '2024-09-02 18:03:50', 'wypłata'),
(18, 2304.83, '2025-01-01 18:03:50', 'wypłata'),
(429, 63.89, '2024-01-23 18:03:50', 'wypłata'),
(143, 1179.85, '2023-07-13 18:03:50', 'wypłata'),
(330, 3492.42, '2023-09-29 18:03:50', 'wpłata'),
(689, 2167.85, '2024-07-10 18:03:50', 'wpłata'),
(540, 1241.27, '2023-06-22 18:03:50', 'wypłata'),
(662, 1768.38, '2024-03-08 18:03:50', 'wpłata'),
(349, 330.79, '2024-08-31 18:03:50', 'wypłata'),
(46, 4369.04, '2023-12-04 18:03:50', 'wpłata'),
(997, 2183.86, '2023-11-15 18:03:50', 'wypłata'),
(12, 4807.71, '2024-01-11 18:03:50', 'wypłata'),
(827, 3770.71, '2025-01-12 18:03:50', 'wypłata'),
(331, 424.5, '2023-06-28 18:03:50', 'wypłata'),
(340, 602.5, '2024-02-28 18:03:50', 'wypłata'),
(17, 4913.74, '2024-07-18 18:03:50', 'wpłata'),
(665, 3950.29, '2023-05-07 18:03:50', 'wypłata'),
(908, 4088.61, '2023-12-26 18:03:50', 'wypłata'),
(341, 2347.82, '2025-01-10 18:03:50', 'wypłata'),
(209, 2476.99, '2023-10-06 18:03:50', 'wypłata'),
(296, 1037.44, '2023-06-11 18:03:50', 'wypłata'),
(779, 3759.89, '2025-01-19 18:03:50', 'wypłata'),
(201, 2933.33, '2024-12-19 18:03:50', 'wypłata'),
(940, 2712.83, '2023-04-27 18:03:50', 'wypłata'),
(675, 619.65, '2023-08-10 18:03:50', 'wpłata'),
(978, 526.18, '2024-11-12 18:03:50', 'wypłata'),
(224, 3132.88, '2024-07-31 18:03:50', 'wypłata'),
(127, 1540.69, '2024-09-20 18:03:50', 'wpłata'),
(478, 1144.48, '2024-08-19 18:03:50', 'wpłata'),
(259, 2134.11, '2023-08-04 18:03:50', 'wpłata'),
(446, 3103.39, '2023-06-21 18:03:50', 'wypłata'),
(912, 3871.06, '2024-02-03 18:03:50', 'wpłata'),
(283, 2688.56, '2025-02-18 18:03:50', 'wpłata'),
(900, 1670.52, '2024-07-22 18:03:50', 'wypłata'),
(219, 1823.73, '2023-11-24 18:03:50', 'wypłata'),
(630, 548.2, '2024-10-21 18:03:50', 'wpłata'),
(883, 1972.02, '2023-10-12 18:03:50', 'wypłata'),
(373, 2506.52, '2023-12-17 18:03:50', 'wpłata'),
(210, 1572.79, '2023-06-15 18:03:50', 'wpłata'),
(190, 2865.62, '2024-05-20 18:03:50', 'wypłata'),
(618, 3553.6, '2024-11-08 18:03:50', 'wypłata'),
(998, 3042.54, '2024-08-04 18:03:50', 'wpłata'),
(832, 202.62, '2023-05-04 18:03:50', 'wpłata'),
(666, 1091.74, '2023-03-17 18:03:50', 'wpłata'),
(286, 4368.47, '2024-04-29 18:03:50', 'wypłata'),
(759, 2186.32, '2024-04-21 18:03:50', 'wpłata'),
(346, 3451.71, '2025-01-03 18:03:50', 'wpłata'),
(170, 2618.06, '2024-03-23 18:03:50', 'wypłata'),
(181, 3440.83, '2023-06-20 18:03:50', 'wypłata'),
(543, 4161.39, '2024-11-27 18:03:50', 'wpłata'),
(804, 545.59, '2023-10-21 18:03:50', 'wypłata'),
(367, 286.92, '2024-09-08 18:03:50', 'wypłata'),
(936, 1219.29, '2024-05-28 18:03:50', 'wpłata'),
(831, 667.95, '2025-02-01 18:03:50', 'wpłata'),
(224, 781.21, '2024-07-23 18:03:50', 'wypłata'),
(431, 1475.27, '2024-05-26 18:03:50', 'wpłata'),
(659, 1147.97, '2024-12-12 18:03:50', 'wypłata'),
(351, 1016.74, '2023-03-29 18:03:50', 'wypłata'),
(606, 1174.97, '2024-10-10 18:03:50', 'wpłata'),
(757, 3160.24, '2024-07-14 18:03:50', 'wypłata'),
(659, 4615.23, '2023-11-19 18:03:50', 'wypłata'),
(103, 4423.52, '2023-05-28 18:03:50', 'wpłata'),
(174, 227.12, '2024-05-28 18:03:50', 'wypłata'),
(363, 2486.18, '2023-08-20 18:03:50', 'wypłata'),
(762, 1129.12, '2023-11-09 18:03:50', 'wpłata'),
(496, 1008.73, '2023-11-03 18:03:50', 'wypłata'),
(203, 890.31, '2023-09-07 18:03:50', 'wypłata'),
(802, 2249.15, '2023-06-08 18:03:50', 'wpłata'),
(863, 4577.37, '2023-04-24 18:03:50', 'wpłata'),
(403, 2761.34, '2025-01-19 18:03:50', 'wpłata'),
(438, 2735.7, '2023-08-12 18:03:50', 'wypłata'),
(317, 3353.68, '2023-08-08 18:03:50', 'wpłata'),
(18, 410.32, '2024-04-25 18:03:50', 'wpłata'),
(334, 761.31, '2024-10-22 18:03:50', 'wpłata'),
(474, 2334.27, '2023-05-08 18:03:50', 'wpłata'),
(569, 707.38, '2023-07-03 18:03:50', 'wypłata'),
(179, 2430.8, '2023-11-09 18:03:50', 'wpłata'),
(472, 3686.37, '2023-03-23 18:03:50', 'wpłata'),
(920, 2789.16, '2024-09-13 18:03:50', 'wpłata'),
(258, 4721.47, '2023-08-15 18:03:50', 'wpłata'),
(641, 551.79, '2024-05-29 18:03:50', 'wpłata'),
(920, 2491.84, '2024-05-11 18:03:50', 'wypłata'),
(801, 3639.08, '2025-01-07 18:03:50', 'wypłata'),
(741, 1724.87, '2024-12-04 18:03:50', 'wypłata'),
(521, 1656.37, '2024-02-14 18:03:50', 'wpłata'),
(646, 1547.63, '2025-01-26 18:03:50', 'wpłata'),
(104, 3725.95, '2023-09-06 18:03:50', 'wpłata'),
(405, 4485.64, '2024-10-05 18:03:50', 'wpłata'),
(6, 757.6, '2023-07-17 18:03:50', 'wypłata'),
(369, 1310.48, '2023-07-17 18:03:50', 'wpłata'),
(56, 870.29, '2023-09-12 18:03:50', 'wpłata'),
(172, 3995.79, '2024-06-19 18:03:50', 'wpłata'),
(891, 3214.58, '2023-06-19 18:03:50', 'wpłata'),
(393, 2796.45, '2023-06-23 18:03:50', 'wpłata'),
(335, 3270.77, '2024-06-28 18:03:50', 'wypłata'),
(844, 1037.01, '2023-08-19 18:03:50', 'wpłata'),
(587, 3550.28, '2023-12-19 18:03:50', 'wypłata'),
(288, 2683.99, '2025-01-02 18:03:50', 'wypłata'),
(506, 1335.71, '2024-03-19 18:03:50', 'wpłata'),
(146, 1902.82, '2023-06-20 18:03:50', 'wpłata'),
(197, 1028.49, '2024-06-17 18:03:50', 'wpłata'),
(598, 244.08, '2023-09-20 18:03:50', 'wpłata'),
(500, 2399.09, '2024-04-11 18:03:50', 'wypłata'),
(218, 4729.7, '2024-11-02 18:03:50', 'wypłata'),
(435, 70.72, '2024-08-10 18:03:50', 'wpłata'),
(815, 1700.23, '2024-06-01 18:03:50', 'wypłata'),
(965, 52.04, '2024-12-09 18:03:50', 'wpłata'),
(703, 3272.18, '2024-08-06 18:03:50', 'wpłata'),
(299, 2417.62, '2023-10-03 18:03:50', 'wpłata'),
(105, 2703.45, '2023-04-14 18:03:50', 'wypłata'),
(244, 1730.04, '2023-12-04 18:03:50', 'wpłata'),
(663, 2909.52, '2024-12-27 18:03:50', 'wpłata'),
(540, 2655.64, '2023-08-24 18:03:50', 'wypłata'),
(16, 2165.42, '2024-03-17 18:03:50', 'wypłata'),
(643, 2861.3, '2024-12-29 18:03:50', 'wpłata'),
(55, 2503.5, '2023-09-05 18:03:50', 'wypłata'),
(989, 2879.28, '2024-04-08 18:03:50', 'wypłata'),
(249, 3459.32, '2024-04-26 18:03:50', 'wypłata'),
(216, 3953.05, '2024-04-29 18:03:50', 'wypłata'),
(583, 896.53, '2024-10-06 18:03:50', 'wypłata'),
(586, 1837.07, '2023-09-22 18:03:50', 'wpłata'),
(132, 1790.52, '2024-08-27 18:03:50', 'wypłata'),
(696, 1560.51, '2023-06-28 18:03:50', 'wypłata'),
(531, 407.38, '2023-07-20 18:03:50', 'wypłata'),
(236, 169.74, '2023-08-29 18:03:50', 'wpłata'),
(272, 1774.07, '2024-05-07 18:03:50', 'wpłata'),
(626, 4641.66, '2024-02-01 18:03:50', 'wpłata'),
(567, 1575.65, '2024-07-27 18:03:50', 'wypłata'),
(655, 2077.19, '2023-12-16 18:03:50', 'wypłata'),
(581, 2833.53, '2023-06-04 18:03:50', 'wpłata'),
(627, 1702.53, '2023-04-10 18:03:50', 'wpłata'),
(712, 446.96, '2024-11-03 18:03:50', 'wpłata'),
(265, 4538.93, '2024-03-07 18:03:50', 'wpłata'),
(383, 2199.0, '2023-06-26 18:03:50', 'wpłata'),
(192, 1383.08, '2025-01-06 18:03:50', 'wpłata'),
(299, 3395.87, '2023-09-18 18:03:50', 'wypłata'),
(943, 1520.04, '2023-04-01 18:03:50', 'wypłata'),
(210, 978.85, '2023-06-14 18:03:50', 'wypłata'),
(679, 1807.03, '2024-01-20 18:03:50', 'wpłata'),
(738, 765.63, '2023-08-27 18:03:50', 'wpłata'),
(723, 2386.82, '2023-09-24 18:03:50', 'wypłata'),
(740, 3444.02, '2024-12-07 18:03:50', 'wpłata'),
(127, 2384.76, '2025-01-10 18:03:50', 'wpłata'),
(515, 4359.46, '2023-10-09 18:03:50', 'wypłata'),
(574, 2019.36, '2024-12-07 18:03:50', 'wypłata'),
(730, 3111.77, '2023-12-12 18:03:50', 'wpłata'),
(253, 3074.93, '2024-06-04 18:03:50', 'wypłata'),
(489, 3336.11, '2023-04-04 18:03:50', 'wpłata'),
(685, 3369.91, '2023-10-31 18:03:50', 'wypłata'),
(195, 3526.11, '2024-07-02 18:03:50', 'wypłata'),
(654, 375.05, '2024-06-10 18:03:50', 'wpłata'),
(327, 220.28, '2025-01-18 18:03:50', 'wpłata'),
(22, 2212.63, '2023-10-02 18:03:50', 'wypłata'),
(705, 4044.73, '2025-01-04 18:03:50', 'wpłata'),
(26, 3919.27, '2025-01-06 18:03:50', 'wpłata'),
(279, 219.05, '2024-11-08 18:03:50', 'wpłata'),
(383, 2730.59, '2024-12-25 18:03:50', 'wypłata'),
(318, 41.3, '2023-03-11 18:03:50', 'wypłata'),
(933, 697.91, '2024-11-09 18:03:50', 'wypłata'),
(750, 209.38, '2024-09-01 18:03:50', 'wypłata'),
(198, 3582.68, '2023-10-28 18:03:50', 'wpłata'),
(938, 3289.97, '2024-09-12 18:03:50', 'wypłata'),
(798, 2068.22, '2024-02-04 18:03:50', 'wypłata'),
(546, 914.39, '2023-05-01 18:03:50', 'wpłata'),
(18, 4025.01, '2024-01-12 18:03:50', 'wypłata'),
(530, 161.7, '2023-07-27 18:03:50', 'wpłata'),
(353, 714.53, '2024-05-01 18:03:50', 'wpłata'),
(314, 301.15, '2023-09-30 18:03:50', 'wypłata'),
(986, 2027.52, '2024-09-11 18:03:50', 'wpłata'),
(494, 4853.39, '2024-02-10 18:03:50', 'wypłata'),
(77, 4776.84, '2023-06-04 18:03:50', 'wypłata'),
(891, 1618.52, '2024-08-29 18:03:50', 'wypłata'),
(103, 2907.98, '2024-07-24 18:03:50', 'wypłata'),
(21, 2851.43, '2024-02-17 18:03:50', 'wpłata'),
(501, 515.7, '2024-09-07 18:03:50', 'wypłata'),
(722, 4238.74, '2024-08-27 18:03:50', 'wpłata'),
(263, 1012.32, '2023-12-18 18:03:50', 'wpłata'),
(675, 1707.21, '2023-03-05 18:03:50', 'wpłata'),
(857, 2667.45, '2023-11-23 18:03:50', 'wpłata'),
(756, 3045.25, '2023-07-22 18:03:50', 'wypłata'),
(990, 2861.08, '2023-11-27 18:03:50', 'wpłata'),
(498, 2375.32, '2024-05-24 18:03:50', 'wypłata'),
(736, 3008.81, '2023-11-29 18:03:50', 'wpłata'),
(873, 4514.03, '2024-12-22 18:03:50', 'wypłata'),
(231, 2410.66, '2024-06-29 18:03:50', 'wpłata'),
(124, 490.1, '2024-10-05 18:03:50', 'wpłata'),
(840, 3559.41, '2024-09-07 18:03:50', 'wypłata'),
(540, 4068.23, '2024-09-28 18:03:50', 'wypłata'),
(332, 1580.78, '2024-04-28 18:03:50', 'wypłata'),
(754, 3412.81, '2023-03-02 18:03:50', 'wpłata'),
(256, 37.66, '2023-05-18 18:03:50', 'wypłata'),
(606, 986.04, '2024-09-26 18:03:50', 'wypłata'),
(338, 1750.37, '2024-10-05 18:03:50', 'wypłata'),
(237, 4644.03, '2024-06-25 18:03:50', 'wpłata'),
(935, 4243.34, '2024-03-02 18:03:50', 'wpłata'),
(352, 2547.48, '2024-01-11 18:03:50', 'wypłata'),
(808, 3115.07, '2023-10-04 18:03:50', 'wpłata'),
(102, 4941.61, '2023-08-14 18:03:50', 'wpłata'),
(959, 1586.53, '2023-03-15 18:03:50', 'wpłata'),
(751, 2661.7, '2024-03-08 18:03:50', 'wpłata'),
(218, 3463.13, '2024-10-26 18:03:50', 'wypłata'),
(950, 2331.28, '2024-03-31 18:03:50', 'wpłata'),
(29, 3133.56, '2023-10-09 18:03:50', 'wypłata'),
(931, 3744.38, '2024-11-17 18:03:50', 'wpłata'),
(302, 1023.46, '2023-03-19 18:03:50', 'wpłata'),
(37, 3651.08, '2023-07-21 18:03:50', 'wpłata'),
(95, 1670.99, '2024-03-28 18:03:50', 'wpłata'),
(927, 2406.26, '2024-08-04 18:03:50', 'wpłata'),
(724, 4982.96, '2023-06-04 18:03:50', 'wypłata'),
(945, 1843.02, '2024-09-02 18:03:50', 'wypłata'),
(555, 1046.59, '2023-08-17 18:03:50', 'wypłata'),
(800, 3376.52, '2024-08-10 18:03:50', 'wypłata'),
(955, 4765.31, '2024-10-02 18:03:50', 'wypłata'),
(985, 1894.81, '2024-10-06 18:03:50', 'wypłata'),
(43, 3489.06, '2024-12-02 18:03:50', 'wpłata'),
(273, 2321.89, '2024-02-13 18:03:50', 'wpłata'),
(216, 3630.77, '2023-10-13 18:03:50', 'wypłata'),
(61, 4069.7, '2024-07-01 18:03:50', 'wpłata'),
(637, 4372.13, '2025-01-30 18:03:50', 'wypłata'),
(386, 1108.4, '2024-09-07 18:03:50', 'wypłata'),
(931, 2786.48, '2023-07-30 18:03:50', 'wypłata'),
(886, 4850.81, '2023-07-25 18:03:50', 'wpłata'),
(964, 2745.55, '2023-08-25 18:03:50', 'wypłata'),
(473, 1750.53, '2025-02-04 18:03:50', 'wypłata'),
(993, 1502.83, '2023-10-07 18:03:50', 'wpłata'),
(466, 2707.72, '2024-02-27 18:03:50', 'wpłata'),
(814, 407.11, '2023-11-23 18:03:50', 'wpłata'),
(139, 1096.53, '2023-10-20 18:03:50', 'wpłata'),
(206, 3317.96, '2024-01-05 18:03:50', 'wpłata'),
(915, 682.31, '2024-08-03 18:03:50', 'wpłata'),
(753, 1755.84, '2025-01-22 18:03:50', 'wpłata'),
(141, 2799.88, '2024-01-28 18:03:50', 'wpłata'),
(418, 2174.23, '2024-11-17 18:03:50', 'wypłata'),
(992, 2785.27, '2023-12-13 18:03:50', 'wpłata'),
(33, 4996.56, '2023-09-12 18:03:50', 'wpłata'),
(155, 3346.16, '2023-05-26 18:03:50', 'wpłata'),
(754, 786.52, '2025-01-24 18:03:50', 'wypłata'),
(560, 4520.11, '2024-06-03 18:03:50', 'wpłata'),
(3, 3324.42, '2024-12-13 18:03:50', 'wypłata'),
(281, 2756.24, '2023-12-27 18:03:50', 'wypłata'),
(59, 1267.79, '2024-10-31 18:03:50', 'wypłata'),
(273, 4657.21, '2023-08-24 18:03:50', 'wypłata'),
(706, 3134.82, '2024-10-30 18:03:50', 'wpłata'),
(320, 4683.03, '2024-09-07 18:03:50', 'wpłata'),
(994, 2699.61, '2024-10-23 18:03:50', 'wpłata'),
(840, 2146.52, '2024-06-19 18:03:50', 'wypłata'),
(381, 2888.67, '2023-11-20 18:03:50', 'wpłata'),
(51, 4306.33, '2023-09-17 18:03:50', 'wypłata'),
(587, 1703.23, '2024-02-14 18:03:50', 'wypłata'),
(176, 4731.66, '2025-01-03 18:03:50', 'wpłata'),
(383, 1364.04, '2023-11-03 18:03:50', 'wpłata'),
(936, 236.92, '2023-07-16 18:03:50', 'wypłata'),
(821, 3549.71, '2023-05-31 18:03:50', 'wpłata'),
(976, 2516.47, '2024-12-27 18:03:50', 'wypłata'),
(880, 910.79, '2023-05-03 18:03:50', 'wpłata'),
(398, 2209.41, '2023-07-03 18:03:50', 'wypłata'),
(795, 550.74, '2024-11-24 18:03:50', 'wpłata'),
(182, 123.18, '2023-03-16 18:03:50', 'wypłata'),
(573, 4588.38, '2023-10-24 18:03:50', 'wpłata'),
(198, 2367.91, '2024-10-15 18:03:50', 'wpłata'),
(867, 4293.96, '2023-06-26 18:03:50', 'wypłata'),
(914, 2431.07, '2023-03-09 18:03:50', 'wypłata'),
(820, 3002.17, '2023-10-31 18:03:50', 'wpłata'),
(666, 2060.35, '2024-08-18 18:03:50', 'wpłata'),
(487, 443.11, '2023-09-10 18:03:50', 'wpłata'),
(149, 4213.6, '2023-12-16 18:03:50', 'wypłata'),
(992, 4253.69, '2023-08-02 18:03:50', 'wypłata'),
(705, 4854.44, '2024-09-08 18:03:50', 'wypłata'),
(978, 2611.93, '2024-05-13 18:03:50', 'wypłata'),
(483, 2831.72, '2023-05-12 18:03:50', 'wypłata'),
(846, 3244.44, '2023-11-19 18:03:50', 'wypłata'),
(454, 4119.35, '2023-12-04 18:03:50', 'wpłata'),
(936, 1450.18, '2023-05-27 18:03:50', 'wypłata'),
(46, 1037.02, '2024-07-02 18:03:50', 'wypłata'),
(635, 1151.86, '2023-10-01 18:03:50', 'wypłata'),
(973, 1810.53, '2024-08-11 18:03:50', 'wypłata'),
(311, 738.71, '2023-10-01 18:03:50', 'wpłata'),
(173, 2883.93, '2024-02-29 18:03:50', 'wypłata'),
(582, 2394.15, '2024-10-27 18:03:50', 'wypłata'),
(785, 350.51, '2024-03-04 18:03:50', 'wypłata'),
(387, 4020.09, '2024-05-17 18:03:50', 'wypłata'),
(980, 119.92, '2023-07-21 18:03:50', 'wpłata'),
(879, 3787.36, '2023-03-18 18:03:50', 'wpłata'),
(133, 865.02, '2025-02-10 18:03:50', 'wpłata'),
(48, 1921.71, '2024-06-22 18:03:50', 'wypłata'),
(258, 1604.3, '2024-11-30 18:03:50', 'wpłata'),
(132, 1594.07, '2023-04-19 18:03:50', 'wpłata'),
(453, 3139.34, '2025-01-08 18:03:50', 'wypłata'),
(681, 3132.84, '2023-10-17 18:03:50', 'wpłata'),
(18, 3389.17, '2025-01-09 18:03:50', 'wypłata'),
(69, 4778.36, '2024-04-21 18:03:50', 'wypłata'),
(906, 3062.61, '2024-10-29 18:03:50', 'wpłata'),
(304, 4621.15, '2024-05-18 18:03:50', 'wypłata'),
(101, 376.37, '2024-02-14 18:03:50', 'wpłata'),
(550, 2856.96, '2023-11-20 18:03:50', 'wypłata'),
(414, 2275.8, '2023-05-27 18:03:50', 'wypłata'),
(258, 1242.41, '2024-08-24 18:03:50', 'wpłata'),
(549, 4195.09, '2023-07-23 18:03:50', 'wypłata'),
(815, 4429.27, '2024-11-09 18:03:50', 'wypłata'),
(303, 3773.37, '2024-01-04 18:03:50', 'wpłata'),
(148, 3898.43, '2023-07-17 18:03:50', 'wpłata'),
(620, 1027.17, '2024-05-04 18:03:50', 'wpłata'),
(963, 227.66, '2024-09-03 18:03:50', 'wpłata'),
(696, 2534.67, '2023-12-08 18:03:50', 'wpłata'),
(807, 3793.4, '2024-06-22 18:03:50', 'wpłata'),
(132, 47.74, '2023-11-21 18:03:50', 'wypłata'),
(613, 3787.43, '2023-07-20 18:03:50', 'wpłata'),
(456, 4511.99, '2024-05-26 18:03:50', 'wypłata'),
(325, 3502.37, '2024-09-29 18:03:50', 'wypłata'),
(374, 3853.4, '2023-11-08 18:03:50', 'wypłata'),
(406, 4088.28, '2023-11-23 18:03:50', 'wypłata'),
(979, 651.51, '2024-09-26 18:03:50', 'wpłata'),
(181, 1375.06, '2024-10-24 18:03:50', 'wypłata'),
(357, 1389.16, '2024-07-15 18:03:50', 'wpłata'),
(768, 1942.64, '2023-09-26 18:03:50', 'wpłata'),
(916, 3163.42, '2023-08-15 18:03:50', 'wypłata'),
(193, 2622.53, '2024-03-14 18:03:50', 'wpłata'),
(87, 1931.5, '2024-01-27 18:03:50', 'wpłata'),
(834, 4243.41, '2023-06-28 18:03:50', 'wpłata'),
(182, 1875.43, '2023-03-08 18:03:50', 'wypłata'),
(452, 2925.73, '2024-03-26 18:03:50', 'wpłata'),
(36, 323.69, '2025-02-16 18:03:50', 'wpłata'),
(145, 950.16, '2023-07-31 18:03:50', 'wpłata'),
(407, 3248.85, '2024-06-10 18:03:50', 'wpłata'),
(820, 4983.22, '2024-06-17 18:03:50', 'wypłata'),
(276, 3158.75, '2024-12-08 18:03:50', 'wypłata'),
(479, 842.49, '2023-08-27 18:03:50', 'wypłata'),
(563, 3703.61, '2024-10-16 18:03:50', 'wpłata'),
(688, 1009.34, '2024-06-16 18:03:50', 'wypłata'),
(366, 389.38, '2023-07-21 18:03:50', 'wpłata'),
(492, 1146.05, '2025-01-07 18:03:50', 'wypłata'),
(449, 4994.8, '2024-04-21 18:03:50', 'wpłata'),
(549, 1221.27, '2024-08-31 18:03:50', 'wpłata'),
(745, 4848.14, '2023-05-12 18:03:50', 'wpłata'),
(35, 3465.1, '2023-07-07 18:03:50', 'wpłata'),
(846, 1225.57, '2024-05-02 18:03:50', 'wypłata'),
(990, 2588.67, '2023-06-07 18:03:50', 'wpłata'),
(28, 4052.84, '2023-10-18 18:03:50', 'wypłata'),
(563, 3768.3, '2023-07-01 18:03:50', 'wpłata'),
(287, 86.36, '2024-04-11 18:03:50', 'wpłata'),
(915, 259.27, '2023-07-09 18:03:50', 'wypłata'),
(8, 2928.73, '2023-08-24 18:03:50', 'wpłata'),
(129, 138.21, '2024-03-22 18:03:50', 'wypłata'),
(222, 2275.88, '2023-09-04 18:03:50', 'wypłata'),
(664, 4752.91, '2024-09-02 18:03:50', 'wpłata'),
(96, 4935.51, '2024-08-07 18:03:50', 'wpłata'),
(527, 2144.32, '2023-09-05 18:03:50', 'wypłata'),
(91, 2155.42, '2024-02-17 18:03:50', 'wypłata'),
(3, 1308.81, '2025-02-06 18:03:50', 'wpłata'),
(670, 4984.26, '2023-05-23 18:03:50', 'wypłata'),
(124, 652.62, '2023-10-13 18:03:50', 'wpłata'),
(73, 2942.81, '2024-08-16 18:03:50', 'wypłata'),
(159, 1515.67, '2024-06-17 18:03:50', 'wpłata'),
(832, 2652.89, '2023-05-01 18:03:50', 'wpłata'),
(495, 334.31, '2025-01-11 18:03:50', 'wypłata'),
(98, 4684.45, '2024-02-04 18:03:50', 'wpłata'),
(765, 2083.26, '2023-11-28 18:03:50', 'wpłata'),
(471, 1878.69, '2023-12-01 18:03:50', 'wpłata'),
(943, 2346.63, '2024-10-22 18:03:50', 'wypłata'),
(755, 637.03, '2025-02-13 18:03:50', 'wpłata'),
(848, 4481.19, '2025-01-29 18:03:50', 'wpłata'),
(844, 4346.97, '2023-06-03 18:03:50', 'wpłata'),
(159, 160.65, '2023-12-02 18:03:50', 'wpłata'),
(566, 3458.27, '2023-04-15 18:03:50', 'wpłata'),
(568, 2047.44, '2023-06-22 18:03:50', 'wpłata'),
(985, 2110.08, '2023-06-17 18:03:50', 'wpłata'),
(157, 85.46, '2024-05-03 18:03:50', 'wpłata'),
(195, 531.88, '2024-12-23 18:03:50', 'wypłata'),
(573, 2349.22, '2024-01-18 18:03:50', 'wypłata'),
(457, 2105.61, '2024-07-06 18:03:50', 'wypłata'),
(101, 1642.49, '2023-09-06 18:03:50', 'wypłata'),
(675, 2191.05, '2024-05-20 18:03:50', 'wypłata'),
(875, 3870.03, '2024-12-24 18:03:50', 'wpłata'),
(333, 734.01, '2024-09-23 18:03:50', 'wypłata'),
(855, 1275.39, '2023-09-15 18:03:50', 'wypłata'),
(206, 3005.25, '2023-03-05 18:03:50', 'wpłata'),
(688, 3404.82, '2024-11-03 18:03:50', 'wypłata'),
(30, 3845.43, '2024-10-22 18:03:50', 'wypłata'),
(614, 1300.98, '2025-01-11 18:03:50', 'wpłata'),
(499, 4783.88, '2024-12-07 18:03:50', 'wypłata'),
(76, 2490.13, '2024-05-26 18:03:50', 'wpłata'),
(325, 147.36, '2023-10-17 18:03:50', 'wypłata'),
(656, 1678.8, '2024-02-16 18:03:50', 'wpłata'),
(44, 1223.63, '2023-11-01 18:03:50', 'wpłata'),
(821, 1638.34, '2023-08-30 18:03:50', 'wypłata'),
(76, 1274.49, '2023-05-27 18:03:50', 'wypłata'),
(620, 2135.42, '2023-07-24 18:03:50', 'wpłata'),
(723, 3267.48, '2024-10-27 18:03:50', 'wypłata'),
(832, 3888.85, '2025-02-04 18:03:50', 'wypłata'),
(678, 1538.68, '2024-09-24 18:03:50', 'wypłata'),
(869, 2737.68, '2024-02-18 18:03:50', 'wypłata'),
(316, 1843.0, '2024-08-14 18:03:50', 'wypłata'),
(216, 4945.44, '2023-04-08 18:03:50', 'wypłata'),
(199, 4485.45, '2024-08-02 18:03:50', 'wpłata'),
(167, 2345.44, '2024-10-15 18:03:50', 'wpłata'),
(611, 3203.93, '2023-11-11 18:03:50', 'wpłata'),
(991, 2684.72, '2024-02-15 18:03:50', 'wypłata'),
(925, 3637.61, '2025-02-02 18:03:50', 'wypłata'),
(873, 276.36, '2023-10-18 18:03:50', 'wypłata'),
(250, 3707.95, '2023-09-15 18:03:50', 'wypłata'),
(360, 4125.86, '2023-06-14 18:03:50', 'wypłata'),
(795, 1018.37, '2024-09-15 18:03:50', 'wypłata'),
(270, 982.67, '2024-09-12 18:03:50', 'wypłata'),
(190, 3377.17, '2023-08-18 18:03:50', 'wpłata'),
(692, 4653.6, '2025-01-15 18:03:50', 'wpłata'),
(188, 4513.88, '2023-10-04 18:03:50', 'wypłata'),
(584, 4255.29, '2025-01-22 18:03:50', 'wpłata'),
(885, 250.23, '2025-02-25 18:03:50', 'wpłata'),
(615, 1228.41, '2025-02-11 18:03:50', 'wpłata'),
(19, 2706.77, '2024-12-13 18:03:50', 'wpłata'),
(15, 4602.42, '2023-05-09 18:03:50', 'wypłata'),
(787, 110.89, '2023-06-15 18:03:50', 'wypłata'),
(419, 3077.23, '2024-03-14 18:03:50', 'wpłata'),
(275, 1506.31, '2024-06-15 18:03:50', 'wpłata'),
(886, 3423.6, '2023-04-08 18:03:50', 'wypłata'),
(894, 3123.28, '2024-01-04 18:03:50', 'wypłata'),
(370, 4010.59, '2023-06-10 18:03:50', 'wypłata'),
(496, 3950.17, '2023-06-12 18:03:50', 'wypłata'),
(262, 1128.18, '2024-02-23 18:03:50', 'wpłata'),
(520, 4152.27, '2023-10-06 18:03:50', 'wypłata'),
(339, 4867.28, '2024-03-27 18:03:50', 'wypłata'),
(509, 3214.66, '2023-06-18 18:03:50', 'wpłata'),
(871, 2612.8, '2024-01-29 18:03:50', 'wpłata'),
(217, 1269.87, '2024-04-08 18:03:50', 'wpłata'),
(167, 2973.38, '2024-02-27 18:03:50', 'wpłata'),
(831, 3532.83, '2024-06-09 18:03:50', 'wypłata'),
(119, 224.37, '2024-02-11 18:03:50', 'wypłata'),
(38, 4390.99, '2023-12-29 18:03:50', 'wypłata'),
(705, 3896.48, '2024-03-29 18:03:50', 'wpłata'),
(848, 2994.64, '2024-12-23 18:03:50', 'wypłata'),
(865, 726.03, '2023-06-10 18:03:50', 'wpłata'),
(657, 2428.9, '2023-04-06 18:03:50', 'wypłata'),
(386, 903.47, '2023-09-25 18:03:50', 'wpłata'),
(187, 2443.67, '2023-03-10 18:03:50', 'wypłata'),
(297, 1000.65, '2023-10-16 18:03:50', 'wpłata'),
(590, 4746.59, '2024-07-22 18:03:50', 'wypłata'),
(131, 2311.31, '2024-05-28 18:03:50', 'wypłata'),
(743, 3996.01, '2024-05-30 18:03:50', 'wpłata'),
(183, 2854.63, '2024-04-18 18:03:50', 'wpłata'),
(741, 2780.98, '2023-08-13 18:03:50', 'wypłata'),
(429, 2276.38, '2024-06-19 18:03:50', 'wpłata'),
(143, 3948.51, '2023-06-23 18:03:50', 'wpłata'),
(780, 428.97, '2024-04-07 18:03:50', 'wypłata'),
(195, 3779.08, '2024-01-26 18:03:50', 'wpłata'),
(375, 4463.38, '2024-11-24 18:03:50', 'wpłata'),
(556, 4404.39, '2024-02-16 18:03:50', 'wypłata'),
(921, 4211.64, '2023-12-15 18:03:50', 'wpłata'),
(971, 1036.03, '2023-07-19 18:03:50', 'wypłata'),
(883, 10.39, '2023-08-15 18:03:50', 'wpłata'),
(712, 1049.65, '2025-02-25 18:03:50', 'wypłata'),
(797, 182.8, '2024-03-09 18:03:50', 'wpłata'),
(539, 2354.67, '2024-10-17 18:03:50', 'wypłata'),
(216, 3624.99, '2025-02-25 18:03:50', 'wpłata'),
(381, 3314.73, '2023-07-23 18:03:50', 'wpłata'),
(959, 3023.18, '2024-07-10 18:03:50', 'wpłata'),
(570, 1840.58, '2024-08-07 18:03:50', 'wypłata'),
(84, 749.06, '2024-08-09 18:03:50', 'wpłata'),
(457, 3041.7, '2024-10-17 18:03:50', 'wpłata'),
(59, 150.16, '2023-09-16 18:03:50', 'wypłata'),
(187, 1198.6, '2023-10-01 18:03:50', 'wypłata'),
(206, 3629.48, '2023-06-26 18:03:50', 'wypłata'),
(120, 4544.14, '2023-04-06 18:03:50', 'wypłata'),
(646, 1576.58, '2024-01-11 18:03:50', 'wypłata'),
(894, 978.89, '2023-03-08 18:03:50', 'wypłata'),
(986, 99.61, '2024-06-22 18:03:50', 'wypłata'),
(177, 1768.81, '2024-06-08 18:03:50', 'wpłata'),
(239, 2684.89, '2024-05-29 18:03:50', 'wypłata'),
(427, 2993.94, '2024-08-21 18:03:50', 'wpłata'),
(703, 4708.3, '2023-05-26 18:03:50', 'wpłata'),
(447, 2540.55, '2023-05-06 18:03:50', 'wypłata'),
(987, 4718.82, '2025-01-16 18:03:50', 'wypłata'),
(128, 4823.32, '2023-05-01 18:03:50', 'wypłata'),
(909, 626.9, '2023-12-25 18:03:50', 'wypłata'),
(850, 3737.67, '2024-06-13 18:03:50', 'wpłata'),
(194, 3195.05, '2024-07-21 18:03:50', 'wypłata'),
(922, 894.34, '2023-04-04 18:03:50', 'wypłata'),
(973, 2202.79, '2024-02-10 18:03:50', 'wpłata'),
(7, 3781.71, '2024-10-08 18:03:50', 'wpłata'),
(275, 1441.8, '2023-10-23 18:03:50', 'wpłata'),
(277, 1644.36, '2023-10-20 18:03:50', 'wpłata'),
(946, 403.98, '2025-01-04 18:03:50', 'wpłata'),
(658, 1085.48, '2025-01-24 18:03:50', 'wypłata'),
(865, 4202.76, '2024-06-27 18:03:50', 'wpłata'),
(29, 2109.19, '2023-09-11 18:03:50', 'wpłata'),
(678, 1359.62, '2025-02-21 18:03:50', 'wpłata'),
(291, 3320.43, '2023-11-11 18:03:50', 'wpłata'),
(127, 3465.55, '2023-09-04 18:03:50', 'wpłata'),
(41, 824.68, '2023-09-04 18:03:50', 'wpłata'),
(290, 2786.28, '2024-11-08 18:03:50', 'wypłata'),
(312, 3894.77, '2023-09-30 18:03:50', 'wpłata'),
(363, 2754.95, '2024-10-30 18:03:50', 'wypłata'),
(326, 1571.78, '2023-09-24 18:03:50', 'wpłata'),
(136, 4740.27, '2023-08-05 18:03:50', 'wpłata'),
(529, 3994.91, '2024-11-19 18:03:50', 'wypłata'),
(674, 2846.92, '2023-09-20 18:03:50', 'wpłata'),
(73, 2441.85, '2024-11-09 18:03:50', 'wpłata'),
(5, 2026.68, '2024-07-25 18:03:50', 'wypłata'),
(286, 4084.77, '2024-10-09 18:03:50', 'wpłata'),
(438, 4059.19, '2025-02-08 18:03:50', 'wypłata'),
(93, 4616.25, '2024-03-20 18:03:50', 'wypłata'),
(129, 386.91, '2024-02-20 18:03:50', 'wpłata'),
(459, 1607.83, '2023-05-30 18:03:50', 'wpłata'),
(793, 3413.03, '2023-09-14 18:03:50', 'wypłata'),
(654, 3496.86, '2024-11-14 18:03:50', 'wpłata'),
(550, 4000.63, '2023-05-11 18:03:50', 'wypłata'),
(113, 2343.11, '2023-05-16 18:03:50', 'wpłata'),
(778, 1679.08, '2025-01-13 18:03:50', 'wpłata'),
(414, 3311.07, '2023-10-04 18:03:50', 'wpłata'),
(1000, 4384.94, '2023-11-11 18:03:50', 'wpłata'),
(478, 3298.71, '2025-02-27 18:03:50', 'wpłata'),
(914, 57.65, '2024-11-02 18:03:50', 'wypłata'),
(305, 4523.82, '2025-02-13 18:03:50', 'wpłata'),
(595, 3854.63, '2023-12-14 18:03:50', 'wypłata'),
(427, 4377.72, '2023-03-26 18:03:50', 'wpłata'),
(561, 370.02, '2024-01-21 18:03:50', 'wypłata'),
(540, 4796.61, '2023-04-30 18:03:50', 'wpłata'),
(616, 3194.93, '2024-12-11 18:03:50', 'wypłata'),
(40, 497.1, '2024-11-06 18:03:50', 'wpłata'),
(814, 4480.16, '2025-01-28 18:03:50', 'wypłata'),
(471, 2579.76, '2024-03-06 18:03:50', 'wpłata'),
(667, 2447.54, '2025-01-10 18:03:50', 'wpłata'),
(717, 1350.84, '2024-03-16 18:03:50', 'wpłata'),
(68, 491.09, '2024-09-16 18:03:50', 'wpłata'),
(564, 75.73, '2024-09-05 18:03:50', 'wypłata'),
(515, 2452.65, '2025-02-28 18:03:50', 'wpłata'),
(382, 2152.93, '2024-11-10 18:03:50', 'wpłata'),
(538, 837.7, '2023-06-23 18:03:50', 'wpłata'),
(699, 2786.48, '2024-09-04 18:03:50', 'wpłata'),
(13, 381.61, '2024-06-15 18:03:50', 'wypłata'),
(505, 2798.13, '2025-01-09 18:03:50', 'wypłata'),
(702, 4564.34, '2024-02-20 18:03:50', 'wypłata'),
(884, 3475.98, '2024-08-28 18:03:50', 'wpłata'),
(859, 1684.61, '2024-06-21 18:03:50', 'wpłata'),
(567, 557.4, '2024-12-30 18:03:50', 'wpłata'),
(821, 361.57, '2023-06-14 18:03:50', 'wypłata'),
(348, 1677.64, '2025-02-18 18:03:50', 'wpłata'),
(150, 4792.06, '2023-05-19 18:03:50', 'wypłata'),
(809, 4059.98, '2023-09-04 18:03:50', 'wypłata'),
(1, 3603.92, '2024-12-04 18:03:50', 'wypłata'),
(324, 2999.26, '2024-12-18 18:03:50', 'wypłata'),
(319, 1701.52, '2024-03-10 18:03:50', 'wypłata'),
(648, 3776.41, '2023-04-18 18:03:50', 'wpłata'),
(286, 3509.07, '2024-03-14 18:03:50', 'wpłata'),
(397, 4378.15, '2024-09-07 18:03:50', 'wpłata'),
(700, 2969.16, '2023-07-27 18:03:50', 'wpłata'),
(559, 4173.12, '2023-11-07 18:03:50', 'wypłata'),
(804, 3631.04, '2023-07-04 18:03:50', 'wypłata'),
(861, 1348.77, '2024-02-29 18:03:50', 'wpłata'),
(36, 4638.31, '2023-05-18 18:03:50', 'wypłata'),
(388, 1709.58, '2024-07-26 18:03:50', 'wypłata'),
(15, 859.62, '2024-12-31 18:03:50', 'wpłata'),
(445, 2532.26, '2023-05-09 18:03:50', 'wpłata'),
(229, 2610.15, '2024-08-06 18:03:50', 'wypłata'),
(29, 2363.64, '2023-09-02 18:03:50', 'wpłata'),
(230, 1392.86, '2023-05-06 18:03:50', 'wypłata'),
(666, 1725.84, '2023-11-09 18:03:50', 'wypłata'),
(777, 4262.15, '2024-06-08 18:03:50', 'wpłata'),
(600, 4800.26, '2025-02-17 18:03:50', 'wypłata'),
(165, 3036.45, '2024-09-20 18:03:50', 'wypłata'),
(847, 1898.29, '2023-05-04 18:03:50', 'wpłata'),
(178, 1049.28, '2025-02-12 18:03:50', 'wpłata'),
(680, 4141.38, '2024-08-30 18:03:50', 'wypłata'),
(716, 711.37, '2023-05-15 18:03:50', 'wypłata'),
(700, 2858.92, '2024-04-23 18:03:50', 'wpłata'),
(145, 289.83, '2023-10-27 18:03:50', 'wpłata'),
(854, 2391.61, '2025-01-07 18:03:50', 'wpłata'),
(277, 429.85, '2023-07-31 18:03:50', 'wypłata'),
(318, 750.73, '2024-04-19 18:03:50', 'wypłata'),
(331, 1487.45, '2023-05-15 18:03:50', 'wypłata'),
(106, 3061.0, '2023-07-20 18:03:50', 'wpłata'),
(860, 1377.89, '2024-12-26 18:03:50', 'wpłata'),
(379, 1311.69, '2024-03-20 18:03:50', 'wypłata'),
(355, 3945.45, '2023-03-12 18:03:50', 'wypłata'),
(268, 1124.07, '2024-04-17 18:03:50', 'wypłata'),
(189, 311.82, '2023-12-17 18:03:50', 'wypłata'),
(243, 3076.18, '2024-09-23 18:03:50', 'wpłata'),
(713, 2853.94, '2023-03-22 18:03:50', 'wypłata'),
(992, 4381.42, '2023-06-05 18:03:50', 'wypłata'),
(105, 4785.39, '2023-03-03 18:03:50', 'wpłata'),
(564, 969.87, '2023-07-24 18:03:50', 'wpłata'),
(322, 873.14, '2024-02-03 18:03:50', 'wypłata'),
(876, 375.7, '2025-01-14 18:03:50', 'wypłata'),
(683, 2377.7, '2023-08-07 18:03:50', 'wypłata'),
(619, 1531.92, '2024-07-29 18:03:50', 'wpłata'),
(713, 2047.3, '2025-02-28 18:03:50', 'wypłata'),
(763, 4527.87, '2023-12-04 18:03:50', 'wpłata'),
(95, 989.13, '2023-05-31 18:03:50', 'wypłata'),
(317, 4714.54, '2023-07-12 18:03:50', 'wpłata'),
(299, 4563.9, '2024-02-29 18:03:50', 'wypłata'),
(874, 2003.6, '2024-07-24 18:03:50', 'wpłata'),
(806, 2596.2, '2023-06-20 18:03:50', 'wypłata'),
(387, 1560.67, '2024-11-30 18:03:50', 'wpłata'),
(817, 1953.26, '2024-02-23 18:03:50', 'wypłata'),
(349, 4415.01, '2024-11-01 18:03:50', 'wypłata'),
(338, 273.59, '2023-07-07 18:03:50', 'wpłata'),
(611, 4276.66, '2024-10-14 18:03:50', 'wypłata'),
(399, 2437.73, '2023-06-17 18:03:50', 'wpłata'),
(442, 4529.89, '2024-09-23 18:03:50', 'wypłata'),
(278, 4190.41, '2024-06-17 18:03:50', 'wypłata'),
(148, 136.06, '2025-01-18 18:03:50', 'wypłata'),
(217, 2992.12, '2023-11-08 18:03:50', 'wypłata'),
(628, 619.75, '2023-07-08 18:03:50', 'wpłata'),
(432, 1196.01, '2023-04-15 18:03:50', 'wypłata'),
(401, 1905.77, '2025-02-26 18:03:50', 'wypłata'),
(535, 2117.98, '2023-07-06 18:03:50', 'wypłata'),
(971, 4579.95, '2024-03-03 18:03:50', 'wpłata'),
(200, 2598.37, '2024-06-16 18:03:50', 'wpłata'),
(104, 3472.28, '2024-11-29 18:03:50', 'wpłata'),
(145, 3435.88, '2024-12-04 18:03:50', 'wpłata'),
(720, 4091.11, '2023-11-09 18:03:50', 'wpłata'),
(502, 4865.99, '2025-02-12 18:03:50', 'wpłata'),
(985, 1260.86, '2023-06-21 18:03:50', 'wpłata'),
(440, 2336.52, '2024-09-23 18:03:50', 'wpłata'),
(323, 3154.7, '2023-12-27 18:03:50', 'wpłata'),
(535, 1701.39, '2023-04-01 18:03:50', 'wypłata'),
(809, 3286.06, '2023-10-17 18:03:50', 'wpłata'),
(629, 1751.73, '2023-10-11 18:03:50', 'wpłata'),
(450, 3840.03, '2023-06-18 18:03:50', 'wpłata'),
(915, 3022.54, '2023-05-20 18:03:50', 'wypłata'),
(152, 325.92, '2024-10-09 18:03:50', 'wypłata'),
(168, 4782.04, '2025-01-02 18:03:50', 'wpłata'),
(770, 2992.95, '2023-07-01 18:03:50', 'wypłata'),
(782, 4351.61, '2024-08-16 18:03:50', 'wypłata'),
(387, 779.75, '2025-10-12 00:00:00', 'wypłata'),
(374, 366.19, '2023-10-08 00:00:00', 'wpłata'),
(851, 363.73, '2024-11-14 00:00:00', 'wpłata'),
(257, 2631.12, '2025-07-24 00:00:00', 'wpłata'),
(855, 3827.46, '2024-07-09 00:00:00', 'wypłata'),
(338, 3393.31, '2025-07-02 00:00:00', 'wypłata'),
(218, 2779.8, '2025-05-29 00:00:00', 'wypłata'),
(516, 2067.25, '2025-03-02 00:00:00', 'wpłata'),
(576, 1621.57, '2023-02-13 00:00:00', 'wpłata'),
(864, 4298.14, '2024-04-12 00:00:00', 'wpłata'),
(200, 4100.98, '2025-09-12 00:00:00', 'wypłata'),
(673, 3569.51, '2023-10-13 00:00:00', 'wpłata'),
(37, 659.26, '2024-09-15 00:00:00', 'wypłata'),
(492, 2952.97, '2024-12-12 00:00:00', 'wypłata'),
(199, 4772.95, '2023-05-09 00:00:00', 'wypłata'),
(543, 1260.76, '2023-02-12 00:00:00', 'wypłata'),
(496, 3475.89, '2025-09-02 00:00:00', 'wpłata'),
(555, 2233.63, '2023-12-21 00:00:00', 'wypłata'),
(833, 2570.53, '2024-09-11 00:00:00', 'wypłata'),
(532, 2229.93, '2025-07-01 00:00:00', 'wypłata'),
(344, 1183.85, '2025-12-24 00:00:00', 'wypłata'),
(536, 3386.59, '2023-04-19 00:00:00', 'wypłata'),
(709, 234.96, '2025-04-20 00:00:00', 'wypłata'),
(192, 2257.2, '2025-12-21 00:00:00', 'wypłata'),
(483, 370.69, '2023-01-13 00:00:00', 'wypłata'),
(538, 1418.12, '2024-06-07 00:00:00', 'wypłata'),
(841, 3551.31, '2024-06-21 00:00:00', 'wypłata'),
(863, 2377.99, '2025-11-06 00:00:00', 'wpłata'),
(177, 1245.11, '2025-08-12 00:00:00', 'wypłata'),
(128, 3723.04, '2023-08-24 00:00:00', 'wypłata'),
(581, 257.21, '2024-09-25 00:00:00', 'wypłata'),
(166, 3577.25, '2025-12-06 00:00:00', 'wypłata'),
(311, 4943.95, '2024-10-04 00:00:00', 'wpłata'),
(10, 2684.53, '2024-12-05 00:00:00', 'wypłata'),
(924, 1696.29, '2024-10-15 00:00:00', 'wypłata'),
(266, 544.95, '2023-04-29 00:00:00', 'wpłata'),
(522, 413.62, '2024-05-27 00:00:00', 'wypłata'),
(351, 1022.83, '2025-09-30 00:00:00', 'wypłata'),
(48, 2419.78, '2025-12-18 00:00:00', 'wpłata'),
(748, 3116.44, '2025-01-31 00:00:00', 'wypłata'),
(809, 615.12, '2025-01-01 00:00:00', 'wypłata'),
(267, 2038.26, '2025-04-08 00:00:00', 'wypłata'),
(476, 1327.59, '2023-01-16 00:00:00', 'wpłata'),
(240, 247.8, '2025-05-23 00:00:00', 'wpłata'),
(149, 1204.43, '2023-01-04 00:00:00', 'wypłata'),
(882, 3410.95, '2024-08-04 00:00:00', 'wpłata'),
(456, 3897.24, '2023-09-14 00:00:00', 'wypłata'),
(361, 1267.83, '2025-10-01 00:00:00', 'wpłata'),
(627, 2528.26, '2024-02-11 00:00:00', 'wypłata'),
(942, 1572.96, '2023-06-29 00:00:00', 'wpłata'),
(23, 3414.78, '2024-08-10 00:00:00', 'wpłata'),
(507, 4524.87, '2024-02-21 00:00:00', 'wypłata'),
(439, 1745.98, '2023-01-24 00:00:00', 'wpłata'),
(210, 3481.77, '2024-08-22 00:00:00', 'wypłata'),
(825, 2591.58, '2024-03-01 00:00:00', 'wypłata'),
(196, 2881.1, '2024-04-27 00:00:00', 'wypłata'),
(392, 3934.53, '2025-09-23 00:00:00', 'wpłata'),
(32, 477.17, '2025-04-06 00:00:00', 'wypłata'),
(346, 694.86, '2024-10-09 00:00:00', 'wpłata'),
(903, 3056.39, '2025-02-21 00:00:00', 'wypłata'),
(65, 570.89, '2023-07-29 00:00:00', 'wpłata'),
(766, 2653.88, '2025-12-23 00:00:00', 'wpłata'),
(182, 1370.74, '2025-07-25 00:00:00', 'wypłata'),
(364, 4092.83, '2025-09-16 00:00:00', 'wypłata'),
(911, 2378.13, '2023-11-24 00:00:00', 'wypłata'),
(843, 3096.38, '2024-07-27 00:00:00', 'wypłata'),
(367, 814.18, '2025-06-24 00:00:00', 'wpłata'),
(633, 2737.98, '2023-04-01 00:00:00', 'wpłata'),
(929, 4578.28, '2025-02-07 00:00:00', 'wpłata'),
(931, 3659.5, '2023-09-30 00:00:00', 'wpłata'),
(423, 595.27, '2023-02-18 00:00:00', 'wpłata'),
(62, 4011.79, '2023-11-05 00:00:00', 'wpłata'),
(824, 717.83, '2025-09-16 00:00:00', 'wpłata'),
(109, 1156.89, '2024-05-16 00:00:00', 'wpłata'),
(747, 2059.0, '2025-05-18 00:00:00', 'wypłata'),
(979, 1871.73, '2023-01-08 00:00:00', 'wpłata'),
(25, 1924.05, '2025-10-05 00:00:00', 'wypłata'),
(667, 474.68, '2024-08-19 00:00:00', 'wypłata'),
(329, 2621.85, '2025-11-28 00:00:00', 'wpłata'),
(831, 2562.49, '2025-01-12 00:00:00', 'wypłata'),
(516, 1901.01, '2025-02-23 00:00:00', 'wypłata'),
(718, 53.76, '2025-03-05 00:00:00', 'wpłata'),
(319, 1620.94, '2023-03-27 00:00:00', 'wpłata'),
(306, 3634.3, '2023-06-22 00:00:00', 'wpłata'),
(812, 4171.26, '2024-11-24 00:00:00', 'wpłata'),
(147, 912.05, '2024-09-24 00:00:00', 'wypłata'),
(20, 4590.91, '2023-12-21 00:00:00', 'wpłata'),
(733, 4736.9, '2023-04-02 00:00:00', 'wpłata'),
(821, 1849.74, '2025-05-04 00:00:00', 'wypłata'),
(200, 144.2, '2025-01-18 00:00:00', 'wypłata'),
(191, 1841.68, '2025-11-15 00:00:00', 'wpłata'),
(750, 1656.98, '2024-01-31 00:00:00', 'wypłata'),
(238, 748.33, '2025-12-30 00:00:00', 'wypłata'),
(464, 4915.87, '2024-09-03 00:00:00', 'wypłata'),
(511, 4060.55, '2025-09-22 00:00:00', 'wypłata'),
(829, 1044.15, '2025-10-10 00:00:00', 'wypłata'),
(912, 1221.11, '2025-03-27 00:00:00', 'wpłata'),
(527, 3534.52, '2023-09-26 00:00:00', 'wpłata'),
(720, 1037.67, '2024-06-22 00:00:00', 'wypłata'),
(339, 3774.19, '2024-09-27 00:00:00', 'wypłata'),
(880, 1086.22, '2025-07-02 00:00:00', 'wpłata'),
(356, 2795.82, '2023-12-05 00:00:00', 'wpłata'),
(881, 4184.66, '2023-11-14 00:00:00', 'wypłata'),
(667, 2174.3, '2025-04-13 00:00:00', 'wpłata'),
(386, 4746.58, '2023-05-08 00:00:00', 'wpłata'),
(657, 2913.01, '2025-06-21 00:00:00', 'wypłata'),
(952, 4874.55, '2023-05-26 00:00:00', 'wypłata'),
(897, 93.12, '2023-04-03 00:00:00', 'wpłata'),
(418, 3619.51, '2024-01-21 00:00:00', 'wpłata'),
(303, 1751.41, '2025-09-25 00:00:00', 'wpłata'),
(551, 1591.61, '2023-03-14 00:00:00', 'wypłata'),
(299, 4496.57, '2025-11-04 00:00:00', 'wypłata'),
(484, 2716.01, '2024-07-04 00:00:00', 'wpłata'),
(573, 3686.71, '2024-07-05 00:00:00', 'wpłata'),
(273, 3818.08, '2025-09-07 00:00:00', 'wpłata'),
(142, 1788.22, '2024-07-08 00:00:00', 'wypłata'),
(248, 1686.55, '2025-03-07 00:00:00', 'wypłata'),
(224, 3294.12, '2025-03-25 00:00:00', 'wpłata'),
(84, 2161.17, '2023-01-28 00:00:00', 'wpłata'),
(486, 1791.68, '2024-01-20 00:00:00', 'wypłata'),
(748, 2961.93, '2024-02-29 00:00:00', 'wpłata'),
(58, 2653.94, '2023-03-22 00:00:00', 'wypłata'),
(240, 1413.35, '2023-10-03 00:00:00', 'wypłata'),
(959, 1002.24, '2024-06-24 00:00:00', 'wypłata'),
(484, 616.05, '2023-02-03 00:00:00', 'wpłata'),
(590, 1118.29, '2025-03-12 00:00:00', 'wypłata'),
(365, 673.59, '2024-04-03 00:00:00', 'wypłata'),
(140, 3687.78, '2024-06-17 00:00:00', 'wpłata'),
(985, 1733.23, '2025-12-20 00:00:00', 'wypłata'),
(365, 3832.06, '2023-04-13 00:00:00', 'wpłata'),
(748, 411.47, '2024-04-02 00:00:00', 'wypłata'),
(241, 4987.03, '2023-02-27 00:00:00', 'wypłata'),
(531, 1905.96, '2025-04-05 00:00:00', 'wpłata'),
(121, 1971.7, '2024-11-06 00:00:00', 'wpłata'),
(939, 4043.12, '2025-01-22 00:00:00', 'wpłata'),
(949, 3118.91, '2024-04-19 00:00:00', 'wypłata'),
(808, 4008.19, '2023-09-15 00:00:00', 'wypłata'),
(305, 3493.37, '2023-12-24 00:00:00', 'wpłata'),
(144, 553.5, '2023-06-03 00:00:00', 'wypłata'),
(1000, 4642.23, '2025-02-24 00:00:00', 'wypłata'),
(322, 3924.05, '2025-05-02 00:00:00', 'wpłata'),
(553, 1947.8, '2023-08-12 00:00:00', 'wypłata'),
(677, 1538.76, '2023-12-11 00:00:00', 'wypłata'),
(756, 2401.44, '2025-03-26 00:00:00', 'wpłata'),
(697, 3546.18, '2025-10-14 00:00:00', 'wpłata'),
(833, 3213.2, '2025-04-07 00:00:00', 'wypłata'),
(635, 4352.24, '2023-07-30 00:00:00', 'wpłata'),
(481, 245.09, '2024-10-14 00:00:00', 'wypłata'),
(160, 427.03, '2024-04-23 00:00:00', 'wypłata'),
(693, 4189.15, '2023-07-16 00:00:00', 'wypłata'),
(452, 2181.91, '2023-11-10 00:00:00', 'wypłata'),
(469, 2496.37, '2023-06-06 00:00:00', 'wpłata'),
(982, 2534.84, '2025-04-25 00:00:00', 'wpłata'),
(215, 2294.62, '2024-06-10 00:00:00', 'wpłata'),
(650, 2323.55, '2023-03-24 00:00:00', 'wpłata'),
(460, 990.83, '2024-10-23 00:00:00', 'wypłata'),
(275, 4475.46, '2025-07-01 00:00:00', 'wpłata'),
(327, 4289.49, '2023-05-13 00:00:00', 'wypłata'),
(382, 1428.92, '2024-02-29 00:00:00', 'wypłata'),
(617, 2075.03, '2024-08-19 00:00:00', 'wypłata'),
(138, 4551.55, '2025-04-14 00:00:00', 'wypłata'),
(176, 4459.37, '2025-02-26 00:00:00', 'wpłata'),
(476, 4963.08, '2025-03-26 00:00:00', 'wypłata'),
(977, 1658.17, '2024-07-09 00:00:00', 'wpłata'),
(980, 1650.89, '2025-09-14 00:00:00', 'wypłata'),
(228, 1737.52, '2024-04-26 00:00:00', 'wpłata'),
(763, 2142.01, '2023-08-06 00:00:00', 'wpłata'),
(151, 4777.14, '2023-08-22 00:00:00', 'wypłata'),
(836, 4634.49, '2024-10-30 00:00:00', 'wpłata'),
(545, 1572.72, '2025-11-21 00:00:00', 'wypłata'),
(825, 1989.49, '2023-06-20 00:00:00', 'wpłata'),
(966, 2739.54, '2024-05-28 00:00:00', 'wypłata'),
(840, 2454.09, '2025-04-29 00:00:00', 'wpłata'),
(639, 2435.69, '2023-11-27 00:00:00', 'wpłata'),
(986, 2359.45, '2025-01-05 00:00:00', 'wypłata'),
(295, 2012.2, '2025-03-16 00:00:00', 'wypłata'),
(985, 4026.7, '2023-07-23 00:00:00', 'wypłata'),
(203, 891.19, '2024-10-26 00:00:00', 'wypłata'),
(612, 485.8, '2023-07-05 00:00:00', 'wypłata'),
(942, 2015.66, '2025-12-25 00:00:00', 'wypłata'),
(927, 2751.13, '2023-12-10 00:00:00', 'wypłata'),
(547, 543.35, '2025-11-22 00:00:00', 'wypłata'),
(678, 4971.15, '2025-07-30 00:00:00', 'wypłata'),
(675, 666.74, '2024-11-10 00:00:00', 'wpłata'),
(965, 3000.27, '2024-03-28 00:00:00', 'wpłata'),
(16, 3918.67, '2025-08-10 00:00:00', 'wypłata'),
(580, 4831.25, '2024-03-01 00:00:00', 'wpłata'),
(529, 3172.55, '2024-09-21 00:00:00', 'wpłata'),
(408, 1366.4, '2024-11-09 00:00:00', 'wpłata'),
(241, 2763.15, '2025-08-21 00:00:00', 'wpłata'),
(757, 1270.96, '2025-10-16 00:00:00', 'wpłata'),
(218, 3038.03, '2023-05-30 00:00:00', 'wypłata'),
(254, 4633.32, '2024-12-12 00:00:00', 'wpłata'),
(793, 4538.17, '2025-12-20 00:00:00', 'wpłata'),
(886, 175.26, '2025-09-16 00:00:00', 'wypłata'),
(535, 2044.43, '2025-07-26 00:00:00', 'wpłata'),
(72, 2969.64, '2024-08-04 00:00:00', 'wpłata'),
(328, 1144.31, '2025-02-26 00:00:00', 'wypłata'),
(46, 4638.09, '2023-06-10 00:00:00', 'wypłata'),
(550, 2421.03, '2023-08-31 00:00:00', 'wpłata'),
(825, 729.61, '2023-10-20 00:00:00', 'wpłata'),
(387, 3802.49, '2025-05-27 00:00:00', 'wpłata'),
(863, 818.62, '2024-12-18 00:00:00', 'wypłata'),
(954, 4341.05, '2024-06-12 00:00:00', 'wpłata'),
(209, 4778.0, '2025-10-06 00:00:00', 'wpłata'),
(326, 1093.45, '2024-10-02 00:00:00', 'wpłata'),
(279, 2363.73, '2025-08-24 00:00:00', 'wypłata'),
(105, 4024.82, '2025-05-20 00:00:00', 'wypłata'),
(170, 3095.77, '2023-11-21 00:00:00', 'wpłata'),
(309, 2767.27, '2025-04-10 00:00:00', 'wypłata'),
(250, 4172.19, '2025-12-15 00:00:00', 'wpłata'),
(634, 1035.65, '2023-03-16 00:00:00', 'wpłata'),
(401, 3391.87, '2024-12-07 00:00:00', 'wypłata'),
(332, 1167.56, '2023-10-05 00:00:00', 'wypłata'),
(538, 968.36, '2024-06-06 00:00:00', 'wypłata'),
(492, 4810.68, '2024-11-27 00:00:00', 'wypłata'),
(507, 289.83, '2023-12-25 00:00:00', 'wpłata'),
(505, 2048.05, '2023-01-11 00:00:00', 'wpłata'),
(943, 3172.3, '2023-06-12 00:00:00', 'wypłata'),
(497, 346.66, '2025-01-20 00:00:00', 'wpłata'),
(618, 3608.56, '2025-10-16 00:00:00', 'wypłata'),
(426, 3244.93, '2024-12-08 00:00:00', 'wpłata'),
(243, 799.4, '2023-01-31 00:00:00', 'wypłata'),
(988, 2002.63, '2024-04-15 00:00:00', 'wpłata'),
(768, 4849.06, '2025-03-03 00:00:00', 'wpłata'),
(405, 2006.48, '2024-02-24 00:00:00', 'wpłata'),
(946, 3487.59, '2025-07-23 00:00:00', 'wpłata'),
(518, 1690.91, '2023-11-28 00:00:00', 'wypłata'),
(319, 1361.86, '2024-01-01 00:00:00', 'wpłata'),
(848, 1642.35, '2025-02-12 00:00:00', 'wpłata'),
(834, 3735.63, '2025-09-25 00:00:00', 'wypłata'),
(265, 939.95, '2023-03-04 00:00:00', 'wpłata'),
(120, 2581.45, '2025-09-24 00:00:00', 'wypłata'),
(168, 2493.96, '2024-03-20 00:00:00', 'wpłata'),
(533, 2548.12, '2024-09-14 00:00:00', 'wpłata'),
(15, 3889.3, '2024-05-02 00:00:00', 'wpłata'),
(338, 249.96, '2023-03-19 00:00:00', 'wpłata'),
(398, 3325.3, '2023-02-14 00:00:00', 'wpłata'),
(838, 2495.64, '2025-04-20 00:00:00', 'wpłata'),
(922, 4806.12, '2025-04-01 00:00:00', 'wpłata'),
(400, 3737.76, '2023-10-29 00:00:00', 'wpłata'),
(862, 2165.94, '2023-12-10 00:00:00', 'wpłata'),
(271, 1513.58, '2025-11-04 00:00:00', 'wypłata'),
(646, 2912.37, '2024-12-09 00:00:00', 'wpłata'),
(968, 406.24, '2024-02-22 00:00:00', 'wypłata'),
(938, 1135.37, '2024-10-13 00:00:00', 'wypłata'),
(815, 3773.14, '2023-11-18 00:00:00', 'wypłata'),
(20, 2514.68, '2025-02-05 00:00:00', 'wpłata'),
(802, 3203.56, '2024-10-15 00:00:00', 'wpłata'),
(955, 162.01, '2025-02-09 00:00:00', 'wpłata'),
(508, 1129.8, '2024-02-09 00:00:00', 'wypłata'),
(231, 1908.18, '2025-01-20 00:00:00', 'wypłata'),
(45, 1343.48, '2025-11-03 00:00:00', 'wypłata'),
(147, 1965.5, '2023-02-06 00:00:00', 'wypłata'),
(343, 181.63, '2023-05-14 00:00:00', 'wypłata'),
(696, 2564.64, '2024-02-14 00:00:00', 'wypłata'),
(456, 1459.56, '2023-09-24 00:00:00', 'wypłata'),
(209, 2380.74, '2024-07-24 00:00:00', 'wypłata'),
(49, 4247.89, '2024-06-08 00:00:00', 'wypłata'),
(709, 1330.32, '2024-01-27 00:00:00', 'wypłata'),
(231, 704.6, '2025-01-21 00:00:00', 'wpłata'),
(607, 3403.83, '2024-01-24 00:00:00', 'wpłata'),
(793, 3786.82, '2025-07-22 00:00:00', 'wypłata'),
(250, 3762.44, '2024-09-09 00:00:00', 'wpłata'),
(593, 1482.0, '2024-01-07 00:00:00', 'wypłata'),
(407, 1707.54, '2024-08-16 00:00:00', 'wpłata'),
(753, 601.59, '2024-05-21 00:00:00', 'wypłata'),
(129, 4444.23, '2025-05-03 00:00:00', 'wpłata'),
(495, 1389.82, '2024-03-31 00:00:00', 'wpłata'),
(618, 157.48, '2023-12-04 00:00:00', 'wpłata'),
(636, 172.54, '2025-01-25 00:00:00', 'wypłata'),
(700, 2167.19, '2023-06-12 00:00:00', 'wypłata'),
(58, 2312.49, '2025-04-11 00:00:00', 'wpłata'),
(601, 3875.4, '2023-09-06 00:00:00', 'wypłata'),
(590, 4703.94, '2024-06-14 00:00:00', 'wpłata'),
(736, 1218.48, '2023-04-06 00:00:00', 'wypłata'),
(168, 4756.83, '2023-10-07 00:00:00', 'wpłata'),
(436, 1287.31, '2023-11-24 00:00:00', 'wpłata'),
(811, 2686.66, '2023-07-07 00:00:00', 'wypłata'),
(746, 3735.99, '2025-09-18 00:00:00', 'wypłata'),
(704, 4788.52, '2025-04-05 00:00:00', 'wypłata'),
(775, 3774.41, '2024-06-19 00:00:00', 'wpłata'),
(224, 2542.15, '2023-07-27 00:00:00', 'wypłata'),
(907, 3873.07, '2024-01-17 00:00:00', 'wpłata'),
(579, 296.31, '2025-10-23 00:00:00', 'wpłata'),
(629, 1703.88, '2025-12-24 00:00:00', 'wypłata'),
(959, 1509.12, '2025-08-21 00:00:00', 'wypłata'),
(272, 992.81, '2025-03-31 00:00:00', 'wypłata'),
(945, 273.03, '2024-01-04 00:00:00', 'wpłata'),
(572, 3083.02, '2025-12-06 00:00:00', 'wypłata'),
(938, 3477.37, '2025-03-23 00:00:00', 'wypłata'),
(45, 4855.89, '2023-11-14 00:00:00', 'wypłata'),
(752, 895.15, '2023-08-24 00:00:00', 'wpłata'),
(659, 729.54, '2023-08-31 00:00:00', 'wpłata'),
(915, 4679.03, '2025-06-05 00:00:00', 'wypłata'),
(159, 110.12, '2024-11-10 00:00:00', 'wypłata'),
(795, 2830.06, '2025-05-06 00:00:00', 'wypłata'),
(882, 2544.18, '2024-01-30 00:00:00', 'wypłata'),
(894, 1593.51, '2023-04-15 00:00:00', 'wpłata'),
(272, 2959.8, '2024-08-12 00:00:00', 'wypłata'),
(502, 707.03, '2024-09-21 00:00:00', 'wypłata'),
(875, 4664.79, '2024-06-04 00:00:00', 'wypłata'),
(425, 159.92, '2025-07-25 00:00:00', 'wpłata'),
(870, 457.03, '2023-02-02 00:00:00', 'wypłata'),
(5, 1660.57, '2024-05-23 00:00:00', 'wpłata'),
(887, 896.3, '2024-06-23 00:00:00', 'wpłata'),
(506, 1253.25, '2024-01-17 00:00:00', 'wpłata'),
(758, 2811.52, '2023-04-20 00:00:00', 'wypłata'),
(23, 4249.13, '2025-05-08 00:00:00', 'wpłata'),
(337, 2265.78, '2024-05-24 00:00:00', 'wpłata'),
(636, 4815.32, '2023-03-11 00:00:00', 'wpłata'),
(579, 3399.99, '2025-01-12 00:00:00', 'wypłata'),
(10, 4674.77, '2023-10-03 00:00:00', 'wpłata'),
(710, 2368.24, '2025-05-21 00:00:00', 'wypłata'),
(800, 1956.48, '2025-04-10 00:00:00', 'wpłata'),
(752, 3243.77, '2025-03-11 00:00:00', 'wypłata'),
(226, 2458.16, '2023-08-06 00:00:00', 'wypłata'),
(698, 2172.28, '2024-08-25 00:00:00', 'wpłata'),
(505, 2414.65, '2025-01-03 00:00:00', 'wpłata'),
(872, 2659.55, '2023-08-22 00:00:00', 'wpłata'),
(666, 3558.88, '2023-02-18 00:00:00', 'wpłata'),
(778, 3701.7, '2023-02-18 00:00:00', 'wypłata'),
(180, 3379.7, '2025-10-09 00:00:00', 'wpłata'),
(422, 2628.15, '2024-01-21 00:00:00', 'wypłata'),
(851, 2555.55, '2023-11-24 00:00:00', 'wypłata'),
(313, 247.06, '2023-07-26 00:00:00', 'wpłata'),
(13, 1551.15, '2023-03-26 00:00:00', 'wypłata'),
(156, 4256.07, '2025-01-17 00:00:00', 'wpłata'),
(70, 4904.23, '2025-06-06 00:00:00', 'wpłata'),
(983, 3488.12, '2025-12-10 00:00:00', 'wypłata'),
(101, 986.58, '2023-10-06 00:00:00', 'wypłata'),
(961, 2548.84, '2025-01-02 00:00:00', 'wypłata'),
(418, 409.87, '2024-05-26 00:00:00', 'wypłata'),
(62, 3761.82, '2024-06-01 00:00:00', 'wypłata'),
(540, 4886.08, '2025-05-19 00:00:00', 'wpłata'),
(609, 2431.89, '2024-10-24 00:00:00', 'wypłata'),
(409, 67.73, '2023-01-30 00:00:00', 'wypłata'),
(145, 4654.89, '2024-09-22 00:00:00', 'wpłata'),
(306, 2091.3, '2025-01-21 00:00:00', 'wpłata'),
(8, 1588.22, '2023-07-27 00:00:00', 'wypłata'),
(547, 4548.24, '2024-03-16 00:00:00', 'wpłata'),
(487, 807.81, '2025-12-15 00:00:00', 'wpłata'),
(899, 1153.55, '2023-12-08 00:00:00', 'wpłata'),
(843, 868.94, '2025-07-20 00:00:00', 'wpłata'),
(816, 4316.47, '2023-10-16 00:00:00', 'wypłata'),
(673, 1992.88, '2024-11-05 00:00:00', 'wpłata'),
(715, 1844.5, '2023-08-30 00:00:00', 'wpłata'),
(453, 4854.57, '2024-05-13 00:00:00', 'wypłata'),
(432, 910.55, '2025-02-28 00:00:00', 'wpłata'),
(857, 105.35, '2023-06-05 00:00:00', 'wpłata'),
(468, 4211.69, '2024-08-28 00:00:00', 'wypłata'),
(1, 673.12, '2024-08-26 00:00:00', 'wypłata'),
(272, 3673.99, '2023-04-05 00:00:00', 'wypłata'),
(569, 4456.1, '2024-03-28 00:00:00', 'wypłata'),
(58, 295.89, '2025-12-21 00:00:00', 'wpłata'),
(910, 3001.07, '2025-09-30 00:00:00', 'wpłata'),
(103, 1935.48, '2024-01-03 00:00:00', 'wypłata'),
(916, 875.75, '2023-05-11 00:00:00', 'wpłata'),
(373, 520.01, '2024-01-07 00:00:00', 'wypłata'),
(137, 2022.21, '2024-10-08 00:00:00', 'wpłata'),
(199, 4885.95, '2023-09-08 00:00:00', 'wypłata'),
(417, 2969.12, '2023-01-10 00:00:00', 'wypłata'),
(274, 4456.22, '2024-05-16 00:00:00', 'wypłata'),
(89, 2600.76, '2025-10-16 00:00:00', 'wpłata'),
(362, 2771.0, '2025-07-03 00:00:00', 'wpłata'),
(413, 3949.41, '2025-12-13 00:00:00', 'wypłata'),
(625, 2480.15, '2023-06-30 00:00:00', 'wpłata'),
(499, 265.53, '2023-05-11 00:00:00', 'wpłata'),
(527, 1906.41, '2024-11-22 00:00:00', 'wpłata'),
(929, 198.44, '2023-12-06 00:00:00', 'wpłata'),
(515, 1282.22, '2025-03-24 00:00:00', 'wypłata'),
(395, 3640.45, '2025-08-12 00:00:00', 'wpłata'),
(156, 4073.8, '2023-08-20 00:00:00', 'wpłata'),
(721, 3798.46, '2025-08-30 00:00:00', 'wpłata'),
(261, 1114.79, '2025-05-29 00:00:00', 'wpłata'),
(872, 4085.43, '2023-06-22 00:00:00', 'wypłata'),
(287, 4805.33, '2023-07-30 00:00:00', 'wpłata'),
(548, 1890.67, '2024-01-01 00:00:00', 'wpłata'),
(327, 2418.8, '2024-05-09 00:00:00', 'wpłata'),
(392, 473.45, '2024-03-14 00:00:00', 'wpłata'),
(996, 3857.1, '2025-09-27 00:00:00', 'wpłata'),
(793, 4159.18, '2023-10-29 00:00:00', 'wypłata'),
(741, 2109.25, '2025-10-30 00:00:00', 'wpłata'),
(428, 3144.42, '2024-08-13 00:00:00', 'wpłata'),
(112, 107.21, '2025-05-02 00:00:00', 'wypłata'),
(581, 1497.27, '2024-07-01 00:00:00', 'wypłata'),
(4, 1994.64, '2024-06-21 00:00:00', 'wypłata'),
(568, 2557.96, '2023-01-03 00:00:00', 'wypłata'),
(113, 4416.13, '2025-11-20 00:00:00', 'wpłata'),
(545, 1606.77, '2023-08-23 00:00:00', 'wypłata'),
(925, 3518.37, '2025-11-02 00:00:00', 'wpłata'),
(791, 457.11, '2023-11-09 00:00:00', 'wpłata'),
(127, 4438.95, '2024-08-27 00:00:00', 'wypłata'),
(534, 3454.1, '2025-12-24 00:00:00', 'wpłata'),
(29, 2318.34, '2025-04-12 00:00:00', 'wpłata'),
(14, 2533.9, '2024-09-06 00:00:00', 'wpłata'),
(128, 3307.02, '2023-03-10 00:00:00', 'wpłata'),
(681, 1369.64, '2025-08-09 00:00:00', 'wypłata'),
(667, 2310.92, '2024-07-29 00:00:00', 'wypłata'),
(759, 2436.31, '2024-05-16 00:00:00', 'wpłata'),
(849, 3677.45, '2025-01-28 00:00:00', 'wpłata'),
(377, 102.93, '2024-11-09 00:00:00', 'wpłata'),
(590, 3965.7, '2024-07-07 00:00:00', 'wpłata'),
(326, 3582.04, '2025-02-19 00:00:00', 'wpłata'),
(404, 929.82, '2025-08-10 00:00:00', 'wpłata'),
(410, 3157.19, '2023-01-02 00:00:00', 'wpłata'),
(558, 3056.13, '2024-07-30 00:00:00', 'wypłata'),
(198, 2738.01, '2025-01-25 00:00:00', 'wypłata'),
(842, 4405.94, '2024-01-23 00:00:00', 'wypłata'),
(543, 98.11, '2025-11-27 00:00:00', 'wypłata'),
(688, 2642.14, '2024-07-25 00:00:00', 'wypłata'),
(481, 1616.2, '2023-11-04 00:00:00', 'wpłata'),
(744, 2048.44, '2025-04-18 00:00:00', 'wpłata'),
(4, 3843.69, '2025-05-09 00:00:00', 'wypłata'),
(786, 4172.56, '2024-09-03 00:00:00', 'wpłata'),
(764, 3105.9, '2023-05-25 00:00:00', 'wpłata'),
(544, 4433.99, '2025-04-11 00:00:00', 'wpłata'),
(647, 2294.4, '2024-02-06 00:00:00', 'wypłata'),
(83, 3251.43, '2023-11-22 00:00:00', 'wpłata'),
(222, 2891.72, '2024-07-29 00:00:00', 'wpłata'),
(37, 793.52, '2024-12-16 00:00:00', 'wpłata'),
(664, 4722.21, '2023-11-13 00:00:00', 'wypłata'),
(882, 3129.74, '2025-04-08 00:00:00', 'wpłata'),
(947, 2696.99, '2024-10-13 00:00:00', 'wpłata'),
(818, 4586.79, '2024-11-14 00:00:00', 'wpłata'),
(772, 4755.51, '2025-11-30 00:00:00', 'wpłata'),
(590, 1822.19, '2025-08-08 00:00:00', 'wpłata'),
(424, 561.15, '2024-07-21 00:00:00', 'wpłata'),
(179, 1006.71, '2024-12-16 00:00:00', 'wypłata'),
(665, 4559.03, '2025-04-08 00:00:00', 'wpłata'),
(491, 1740.15, '2024-12-28 00:00:00', 'wypłata'),
(421, 3178.91, '2025-03-31 00:00:00', 'wpłata'),
(345, 3181.79, '2024-02-23 00:00:00', 'wpłata'),
(560, 2033.65, '2025-12-22 00:00:00', 'wpłata'),
(122, 2309.1, '2023-05-19 00:00:00', 'wpłata'),
(989, 1980.84, '2023-02-10 00:00:00', 'wpłata'),
(867, 4940.37, '2025-09-19 00:00:00', 'wpłata'),
(603, 330.51, '2023-09-10 00:00:00', 'wypłata'),
(574, 2547.1, '2025-05-30 00:00:00', 'wpłata'),
(557, 1737.26, '2023-03-21 00:00:00', 'wpłata'),
(584, 183.56, '2025-04-12 00:00:00', 'wypłata'),
(310, 3611.47, '2024-06-03 00:00:00', 'wpłata'),
(645, 4318.54, '2025-07-02 00:00:00', 'wpłata'),
(889, 4706.53, '2024-11-26 00:00:00', 'wpłata'),
(887, 4365.16, '2023-09-25 00:00:00', 'wypłata'),
(830, 426.95, '2025-09-25 00:00:00', 'wypłata'),
(49, 2778.27, '2023-09-06 00:00:00', 'wypłata'),
(67, 4746.78, '2024-06-05 00:00:00', 'wpłata'),
(535, 2550.91, '2023-03-25 00:00:00', 'wypłata'),
(522, 2216.94, '2024-03-09 00:00:00', 'wpłata'),
(14, 3583.62, '2023-11-26 00:00:00', 'wypłata'),
(254, 1861.12, '2025-11-03 00:00:00', 'wypłata'),
(28, 441.07, '2023-06-03 00:00:00', 'wpłata'),
(970, 1779.99, '2024-11-04 00:00:00', 'wypłata'),
(442, 2581.11, '2025-03-06 00:00:00', 'wpłata'),
(739, 2923.14, '2023-08-17 00:00:00', 'wpłata'),
(871, 4070.8, '2023-03-24 00:00:00', 'wpłata'),
(487, 166.97, '2023-02-11 00:00:00', 'wpłata'),
(628, 4518.45, '2023-04-26 00:00:00', 'wypłata'),
(291, 4450.23, '2025-11-28 00:00:00', 'wpłata'),
(953, 1542.29, '2023-09-09 00:00:00', 'wypłata'),
(129, 2110.34, '2025-02-14 00:00:00', 'wpłata'),
(76, 932.47, '2025-04-02 00:00:00', 'wypłata'),
(523, 249.65, '2023-10-14 00:00:00', 'wypłata'),
(372, 4718.87, '2025-04-01 00:00:00', 'wypłata'),
(48, 3598.29, '2025-09-07 00:00:00', 'wypłata'),
(788, 1686.47, '2025-06-29 00:00:00', 'wpłata'),
(282, 3793.8, '2024-01-18 00:00:00', 'wypłata'),
(699, 1967.1, '2025-12-24 00:00:00', 'wypłata'),
(754, 1822.54, '2024-08-01 00:00:00', 'wypłata'),
(335, 2411.9, '2024-10-12 00:00:00', 'wypłata'),
(897, 3612.14, '2023-02-10 00:00:00', 'wypłata'),
(260, 3413.17, '2024-07-18 00:00:00', 'wypłata'),
(208, 111.44, '2024-12-08 00:00:00', 'wpłata'),
(472, 1712.53, '2024-08-28 00:00:00', 'wpłata'),
(939, 1376.84, '2023-05-27 00:00:00', 'wypłata'),
(706, 3713.84, '2024-04-03 00:00:00', 'wpłata'),
(332, 3504.0, '2024-07-28 00:00:00', 'wpłata'),
(771, 1914.67, '2024-08-28 00:00:00', 'wypłata'),
(30, 1970.43, '2024-02-02 00:00:00', 'wypłata'),
(673, 3650.49, '2023-03-20 00:00:00', 'wpłata'),
(760, 4875.02, '2024-09-29 00:00:00', 'wpłata'),
(5, 945.23, '2025-11-27 00:00:00', 'wypłata'),
(464, 455.59, '2024-04-17 00:00:00', 'wypłata'),
(576, 3499.93, '2025-02-25 00:00:00', 'wypłata'),
(845, 4806.85, '2023-09-05 00:00:00', 'wpłata'),
(846, 4312.54, '2023-02-27 00:00:00', 'wypłata'),
(8, 4618.71, '2025-09-26 00:00:00', 'wypłata'),
(31, 1952.91, '2024-12-22 00:00:00', 'wypłata'),
(733, 1180.49, '2024-04-03 00:00:00', 'wypłata'),
(152, 488.73, '2024-08-01 00:00:00', 'wpłata'),
(330, 311.44, '2025-05-13 00:00:00', 'wypłata'),
(24, 2562.05, '2025-12-29 00:00:00', 'wpłata'),
(843, 1257.8, '2025-06-14 00:00:00', 'wypłata'),
(351, 4925.38, '2023-02-03 00:00:00', 'wpłata'),
(289, 2120.72, '2025-07-31 00:00:00', 'wpłata'),
(907, 1606.77, '2024-12-18 00:00:00', 'wpłata'),
(583, 244.37, '2024-12-09 00:00:00', 'wypłata'),
(398, 1269.95, '2024-04-22 00:00:00', 'wpłata'),
(877, 4548.82, '2025-12-29 00:00:00', 'wpłata'),
(784, 1624.13, '2024-04-26 00:00:00', 'wpłata'),
(441, 2343.34, '2024-09-03 00:00:00', 'wpłata'),
(779, 2558.02, '2025-03-21 00:00:00', 'wypłata'),
(606, 2778.38, '2023-04-17 00:00:00', 'wypłata'),
(512, 550.56, '2025-08-22 00:00:00', 'wpłata'),
(886, 2531.79, '2024-05-31 00:00:00', 'wypłata'),
(899, 3598.4, '2024-07-04 00:00:00', 'wypłata'),
(377, 3235.24, '2024-04-23 00:00:00', 'wypłata'),
(267, 2318.23, '2023-11-24 00:00:00', 'wypłata'),
(181, 3007.49, '2023-11-03 00:00:00', 'wpłata'),
(738, 3601.57, '2024-05-27 00:00:00', 'wpłata'),
(835, 1151.91, '2025-01-01 00:00:00', 'wpłata'),
(175, 3051.15, '2024-02-10 00:00:00', 'wypłata'),
(11, 4598.09, '2023-09-28 00:00:00', 'wpłata'),
(902, 2061.25, '2025-01-11 00:00:00', 'wpłata'),
(690, 1455.85, '2024-03-22 00:00:00', 'wpłata'),
(571, 1085.62, '2023-12-06 00:00:00', 'wypłata'),
(553, 4815.05, '2024-09-07 00:00:00', 'wypłata'),
(785, 3285.26, '2024-07-30 00:00:00', 'wypłata'),
(981, 166.98, '2023-07-11 00:00:00', 'wpłata'),
(211, 3086.54, '2024-07-03 00:00:00', 'wpłata'),
(822, 2851.94, '2023-05-29 00:00:00', 'wpłata'),
(812, 4828.17, '2024-12-02 00:00:00', 'wypłata'),
(759, 956.8, '2025-05-23 00:00:00', 'wypłata'),
(642, 3643.11, '2025-12-22 00:00:00', 'wpłata'),
(583, 3576.01, '2023-05-03 00:00:00', 'wypłata'),
(269, 200.5, '2024-11-03 00:00:00', 'wpłata'),
(162, 1929.99, '2023-01-15 00:00:00', 'wypłata'),
(100, 434.54, '2025-04-12 00:00:00', 'wypłata'),
(852, 962.43, '2023-09-28 00:00:00', 'wpłata'),
(766, 1012.31, '2024-03-17 00:00:00', 'wypłata'),
(282, 2615.92, '2025-07-22 00:00:00', 'wpłata'),
(694, 1367.87, '2023-10-22 00:00:00', 'wypłata'),
(219, 4147.38, '2025-04-19 00:00:00', 'wpłata'),
(782, 4541.88, '2023-09-23 00:00:00', 'wypłata'),
(266, 4008.12, '2023-01-12 00:00:00', 'wypłata'),
(703, 4055.75, '2024-03-02 00:00:00', 'wpłata'),
(131, 3306.17, '2023-03-28 00:00:00', 'wpłata'),
(254, 367.76, '2025-08-05 00:00:00', 'wypłata'),
(306, 1119.28, '2025-01-01 00:00:00', 'wpłata'),
(468, 3845.68, '2023-07-01 00:00:00', 'wpłata'),
(211, 3101.0, '2025-11-23 00:00:00', 'wpłata'),
(225, 2009.46, '2025-12-31 00:00:00', 'wpłata'),
(118, 523.65, '2024-10-04 00:00:00', 'wpłata'),
(59, 4760.18, '2023-12-07 00:00:00', 'wypłata'),
(876, 3515.87, '2023-10-15 00:00:00', 'wypłata'),
(772, 1626.88, '2023-01-06 00:00:00', 'wpłata'),
(70, 3815.73, '2025-01-09 00:00:00', 'wpłata'),
(7, 120.76, '2023-09-12 00:00:00', 'wpłata'),
(567, 1317.88, '2025-11-02 00:00:00', 'wpłata'),
(683, 3155.98, '2023-04-02 00:00:00', 'wypłata'),
(27, 4735.16, '2024-09-25 00:00:00', 'wpłata'),
(873, 1750.05, '2025-06-20 00:00:00', 'wpłata'),
(542, 51.4, '2025-09-26 00:00:00', 'wpłata'),
(717, 2860.51, '2024-10-09 00:00:00', 'wypłata'),
(639, 3099.02, '2025-05-13 00:00:00', 'wpłata'),
(807, 2266.94, '2025-03-16 00:00:00', 'wpłata'),
(618, 2467.51, '2025-01-09 00:00:00', 'wypłata'),
(417, 864.21, '2023-01-01 00:00:00', 'wypłata'),
(546, 1552.71, '2025-06-28 00:00:00', 'wypłata'),
(580, 651.06, '2024-12-03 00:00:00', 'wypłata'),
(956, 3501.48, '2023-05-08 00:00:00', 'wypłata'),
(721, 4756.75, '2024-08-03 00:00:00', 'wpłata'),
(339, 4224.71, '2025-12-11 00:00:00', 'wpłata'),
(160, 3580.4, '2025-04-02 00:00:00', 'wypłata'),
(372, 4531.66, '2024-08-04 00:00:00', 'wpłata'),
(437, 4263.49, '2023-04-23 00:00:00', 'wpłata'),
(47, 4970.03, '2024-08-12 00:00:00', 'wypłata'),
(905, 4816.06, '2025-06-25 00:00:00', 'wpłata'),
(602, 4818.59, '2023-04-05 00:00:00', 'wypłata'),
(213, 2634.71, '2024-09-18 00:00:00', 'wypłata'),
(770, 2896.71, '2023-07-20 00:00:00', 'wypłata'),
(194, 4871.57, '2025-01-07 00:00:00', 'wpłata'),
(598, 2492.77, '2024-12-24 00:00:00', 'wpłata'),
(307, 3741.65, '2025-08-03 00:00:00', 'wypłata'),
(730, 3961.49, '2023-10-30 00:00:00', 'wpłata'),
(589, 3334.85, '2025-03-15 00:00:00', 'wypłata'),
(301, 3629.6, '2025-01-22 00:00:00', 'wpłata'),
(502, 2227.59, '2023-01-07 00:00:00', 'wypłata'),
(181, 214.67, '2025-06-05 00:00:00', 'wypłata'),
(831, 4407.7, '2025-08-28 00:00:00', 'wpłata'),
(647, 1442.23, '2024-02-09 00:00:00', 'wypłata'),
(233, 1043.57, '2023-02-07 00:00:00', 'wypłata'),
(4, 3623.47, '2023-01-14 00:00:00', 'wypłata'),
(649, 3459.52, '2025-12-31 00:00:00', 'wpłata'),
(121, 2570.12, '2023-03-25 00:00:00', 'wypłata'),
(882, 1351.76, '2023-11-27 00:00:00', 'wypłata'),
(943, 3507.19, '2025-02-20 00:00:00', 'wypłata'),
(442, 1413.35, '2024-04-27 00:00:00', 'wypłata'),
(829, 1901.93, '2025-12-17 00:00:00', 'wypłata'),
(205, 3525.36, '2025-05-29 00:00:00', 'wypłata'),
(523, 2538.17, '2023-03-16 00:00:00', 'wypłata'),
(983, 4136.89, '2023-07-25 00:00:00', 'wypłata'),
(533, 4076.44, '2023-03-03 00:00:00', 'wypłata'),
(320, 1558.83, '2024-01-12 00:00:00', 'wpłata'),
(154, 3200.78, '2025-05-24 00:00:00', 'wypłata'),
(133, 620.8, '2024-02-23 00:00:00', 'wypłata'),
(897, 1398.64, '2023-12-22 00:00:00', 'wypłata'),
(395, 2068.51, '2024-08-31 00:00:00', 'wpłata'),
(252, 4658.94, '2023-07-22 00:00:00', 'wpłata'),
(649, 2091.52, '2025-01-10 00:00:00', 'wypłata'),
(704, 4543.65, '2024-08-16 00:00:00', 'wpłata'),
(654, 2712.44, '2023-11-10 00:00:00', 'wypłata'),
(900, 1921.32, '2023-12-22 00:00:00', 'wypłata'),
(704, 1415.92, '2024-11-12 00:00:00', 'wpłata'),
(461, 693.09, '2025-02-20 00:00:00', 'wpłata'),
(166, 3502.89, '2025-05-05 00:00:00', 'wpłata'),
(310, 3800.88, '2025-05-21 00:00:00', 'wypłata'),
(759, 1741.24, '2025-04-16 00:00:00', 'wypłata'),
(7, 1504.83, '2024-08-02 00:00:00', 'wypłata'),
(485, 2866.08, '2023-01-26 00:00:00', 'wpłata'),
(584, 3371.54, '2025-10-16 00:00:00', 'wypłata'),
(120, 3399.93, '2024-05-29 00:00:00', 'wpłata'),
(499, 2905.15, '2023-12-13 00:00:00', 'wpłata'),
(564, 4798.93, '2025-04-25 00:00:00', 'wpłata'),
(190, 2262.08, '2023-09-06 00:00:00', 'wpłata'),
(336, 1210.31, '2025-02-12 00:00:00', 'wpłata'),
(886, 1305.05, '2025-07-05 00:00:00', 'wypłata'),
(599, 3089.81, '2023-07-06 00:00:00', 'wpłata'),
(563, 301.26, '2024-08-28 00:00:00', 'wpłata'),
(98, 3000.73, '2025-06-16 00:00:00', 'wpłata'),
(224, 2445.2, '2025-07-02 00:00:00', 'wypłata'),
(975, 1157.99, '2024-09-16 00:00:00', 'wpłata'),
(447, 2511.23, '2024-01-02 00:00:00', 'wypłata'),
(953, 3084.27, '2023-09-09 00:00:00', 'wypłata'),
(821, 318.32, '2023-12-25 00:00:00', 'wypłata'),
(218, 1481.83, '2024-07-18 00:00:00', 'wypłata'),
(321, 2366.57, '2025-11-24 00:00:00', 'wpłata'),
(507, 4451.69, '2025-11-01 00:00:00', 'wypłata'),
(647, 4613.6, '2024-09-27 00:00:00', 'wpłata'),
(891, 3957.59, '2023-09-12 00:00:00', 'wpłata'),
(358, 4467.15, '2025-02-04 00:00:00', 'wpłata'),
(256, 4355.95, '2024-04-29 00:00:00', 'wpłata'),
(687, 3848.7, '2023-08-28 00:00:00', 'wpłata'),
(549, 1475.26, '2024-02-29 00:00:00', 'wpłata'),
(830, 3632.84, '2023-07-06 00:00:00', 'wypłata'),
(654, 2567.82, '2025-06-25 00:00:00', 'wpłata'),
(8, 2790.79, '2025-07-25 00:00:00', 'wypłata'),
(283, 1663.08, '2023-02-01 00:00:00', 'wypłata'),
(910, 1251.1, '2023-04-14 00:00:00', 'wypłata'),
(551, 1696.08, '2024-04-14 00:00:00', 'wpłata'),
(233, 105.67, '2025-09-30 00:00:00', 'wypłata'),
(360, 3243.01, '2024-02-19 00:00:00', 'wypłata'),
(81, 619.63, '2024-02-16 00:00:00', 'wypłata'),
(445, 3422.93, '2025-06-12 00:00:00', 'wpłata'),
(175, 2091.25, '2023-11-01 00:00:00', 'wypłata'),
(343, 2242.62, '2023-08-24 00:00:00', 'wypłata'),
(423, 1777.95, '2024-01-14 00:00:00', 'wpłata'),
(260, 1027.77, '2023-04-28 00:00:00', 'wpłata'),
(337, 3595.89, '2023-06-29 00:00:00', 'wpłata'),
(990, 3982.71, '2023-12-04 00:00:00', 'wpłata'),
(916, 2315.34, '2025-09-19 00:00:00', 'wpłata'),
(615, 702.88, '2024-03-28 00:00:00', 'wypłata'),
(284, 475.26, '2023-05-20 00:00:00', 'wypłata'),
(102, 1463.19, '2023-07-22 00:00:00', 'wypłata'),
(658, 3813.76, '2024-03-05 00:00:00', 'wypłata'),
(521, 1721.78, '2025-10-21 00:00:00', 'wypłata'),
(164, 4133.8, '2025-12-09 00:00:00', 'wpłata'),
(529, 1688.52, '2023-05-16 00:00:00', 'wypłata'),
(19, 578.9, '2024-03-03 00:00:00', 'wpłata'),
(846, 4031.26, '2023-08-12 00:00:00', 'wypłata'),
(335, 2466.58, '2024-12-18 00:00:00', 'wpłata'),
(887, 1510.4, '2023-07-20 00:00:00', 'wpłata'),
(622, 3794.88, '2025-12-08 00:00:00', 'wpłata'),
(201, 1902.58, '2024-04-20 00:00:00', 'wypłata'),
(203, 3624.35, '2024-06-22 00:00:00', 'wpłata'),
(664, 430.34, '2024-10-08 00:00:00', 'wypłata'),
(219, 1190.49, '2024-03-02 00:00:00', 'wypłata'),
(260, 4395.03, '2023-09-06 00:00:00', 'wpłata'),
(690, 4826.15, '2023-07-21 00:00:00', 'wypłata'),
(433, 929.74, '2023-03-27 00:00:00', 'wypłata'),
(915, 665.24, '2024-12-11 00:00:00', 'wpłata'),
(946, 753.81, '2025-10-14 00:00:00', 'wpłata'),
(780, 2991.44, '2024-06-19 00:00:00', 'wpłata'),
(672, 1898.89, '2024-10-16 00:00:00', 'wypłata'),
(764, 333.4, '2023-01-09 00:00:00', 'wpłata'),
(974, 4636.73, '2023-05-24 00:00:00', 'wpłata'),
(545, 1838.32, '2023-09-20 00:00:00', 'wpłata'),
(790, 994.85, '2023-10-25 00:00:00', 'wpłata'),
(529, 2221.18, '2023-09-30 00:00:00', 'wypłata'),
(241, 4246.11, '2023-03-31 00:00:00', 'wpłata'),
(578, 3678.35, '2025-10-23 00:00:00', 'wpłata'),
(507, 443.29, '2023-08-08 00:00:00', 'wypłata'),
(799, 2129.09, '2024-05-04 00:00:00', 'wpłata'),
(561, 4448.53, '2025-02-20 00:00:00', 'wypłata'),
(600, 654.47, '2025-04-08 00:00:00', 'wpłata'),
(150, 3770.2, '2023-09-10 00:00:00', 'wpłata'),
(75, 4590.49, '2023-06-26 00:00:00', 'wypłata'),
(547, 2053.75, '2023-01-28 00:00:00', 'wypłata'),
(23, 3034.02, '2024-12-10 00:00:00', 'wypłata'),
(651, 1766.27, '2023-05-22 00:00:00', 'wypłata'),
(112, 700.85, '2025-10-25 00:00:00', 'wypłata'),
(688, 3675.18, '2024-12-17 00:00:00', 'wypłata'),
(170, 488.8, '2025-05-17 00:00:00', 'wpłata'),
(54, 995.46, '2024-10-23 00:00:00', 'wpłata'),
(552, 3603.31, '2023-11-08 00:00:00', 'wypłata'),
(771, 4390.64, '2023-08-29 00:00:00', 'wpłata'),
(184, 4773.49, '2024-12-11 00:00:00', 'wpłata'),
(652, 4856.19, '2023-09-30 00:00:00', 'wpłata'),
(118, 4452.21, '2025-09-09 00:00:00', 'wypłata'),
(691, 1012.82, '2023-07-01 00:00:00', 'wpłata'),
(431, 2490.7, '2023-03-21 00:00:00', 'wpłata'),
(928, 945.37, '2024-07-22 00:00:00', 'wpłata'),
(750, 3838.37, '2025-12-08 00:00:00', 'wypłata'),
(988, 3880.36, '2024-03-30 00:00:00', 'wpłata'),
(22, 1467.5, '2023-11-09 00:00:00', 'wypłata'),
(500, 1120.31, '2024-03-15 00:00:00', 'wpłata'),
(889, 327.09, '2024-04-14 00:00:00', 'wypłata'),
(545, 4087.2, '2023-06-06 00:00:00', 'wpłata'),
(894, 1180.64, '2023-06-28 00:00:00', 'wypłata'),
(201, 4061.98, '2023-05-21 00:00:00', 'wpłata'),
(996, 4853.45, '2024-06-29 00:00:00', 'wpłata'),
(808, 3389.77, '2025-07-26 00:00:00', 'wpłata'),
(32, 3372.8, '2025-05-09 00:00:00', 'wypłata'),
(4, 1498.85, '2023-12-06 00:00:00', 'wpłata'),
(415, 191.97, '2023-05-19 00:00:00', 'wpłata'),
(817, 3280.75, '2023-06-02 00:00:00', 'wpłata'),
(122, 198.23, '2025-11-16 00:00:00', 'wpłata'),
(456, 154.95, '2023-09-03 00:00:00', 'wpłata'),
(389, 1981.06, '2025-04-20 00:00:00', 'wypłata'),
(644, 1768.02, '2025-06-27 00:00:00', 'wpłata'),
(375, 542.86, '2024-11-26 00:00:00', 'wypłata'),
(268, 3401.69, '2024-10-08 00:00:00', 'wypłata'),
(346, 1756.47, '2025-07-27 00:00:00', 'wpłata'),
(694, 1895.18, '2024-10-08 00:00:00', 'wypłata'),
(378, 3080.67, '2025-11-23 00:00:00', 'wpłata'),
(314, 368.01, '2023-09-19 00:00:00', 'wpłata'),
(586, 3426.8, '2024-03-04 00:00:00', 'wpłata'),
(999, 2500.2, '2025-10-06 00:00:00', 'wypłata'),
(72, 437.54, '2024-06-18 00:00:00', 'wpłata'),
(709, 2322.21, '2024-10-14 00:00:00', 'wpłata'),
(391, 2727.78, '2023-09-18 00:00:00', 'wpłata'),
(914, 2972.23, '2024-05-15 00:00:00', 'wypłata'),
(28, 4290.44, '2024-02-27 00:00:00', 'wypłata'),
(184, 2792.52, '2023-11-29 00:00:00', 'wypłata'),
(311, 3319.81, '2023-03-31 00:00:00', 'wypłata'),
(351, 2409.89, '2024-11-24 00:00:00', 'wypłata'),
(542, 4053.29, '2024-01-26 00:00:00', 'wpłata'),
(450, 4435.17, '2024-12-11 00:00:00', 'wypłata'),
(758, 913.43, '2024-06-27 00:00:00', 'wypłata'),
(919, 2408.54, '2024-05-07 00:00:00', 'wpłata'),
(371, 2499.73, '2024-09-09 00:00:00', 'wypłata'),
(918, 3193.83, '2023-01-16 00:00:00', 'wypłata'),
(572, 2230.74, '2024-05-10 00:00:00', 'wpłata'),
(844, 2531.1, '2025-08-27 00:00:00', 'wypłata'),
(330, 1772.08, '2023-05-02 00:00:00', 'wypłata'),
(756, 4606.79, '2024-05-07 00:00:00', 'wypłata'),
(782, 3059.39, '2024-06-30 00:00:00', 'wpłata'),
(120, 605.15, '2023-09-21 00:00:00', 'wpłata'),
(898, 1420.96, '2025-08-30 00:00:00', 'wypłata'),
(418, 3488.0, '2024-11-18 00:00:00', 'wpłata'),
(441, 1802.76, '2024-06-11 00:00:00', 'wpłata'),
(481, 4736.45, '2025-05-05 00:00:00', 'wpłata'),
(914, 2722.35, '2025-03-19 00:00:00', 'wypłata'),
(209, 4151.82, '2023-01-30 00:00:00', 'wpłata'),
(72, 4327.0, '2024-04-24 00:00:00', 'wypłata'),
(386, 991.87, '2025-12-18 00:00:00', 'wypłata'),
(775, 420.42, '2024-02-20 00:00:00', 'wpłata'),
(428, 2989.12, '2024-09-16 00:00:00', 'wpłata'),
(241, 1510.44, '2025-02-16 00:00:00', 'wypłata'),
(108, 468.24, '2025-09-07 00:00:00', 'wpłata'),
(589, 4243.21, '2023-01-19 00:00:00', 'wpłata'),
(198, 2011.69, '2024-09-25 00:00:00', 'wypłata'),
(345, 285.97, '2025-08-17 00:00:00', 'wypłata'),
(799, 4276.02, '2025-05-27 00:00:00', 'wpłata'),
(914, 4911.9, '2024-11-12 00:00:00', 'wypłata'),
(469, 4579.68, '2025-07-11 00:00:00', 'wypłata'),
(338, 510.04, '2025-04-24 00:00:00', 'wpłata'),
(561, 1184.02, '2023-06-13 00:00:00', 'wypłata'),
(729, 1148.08, '2023-11-26 00:00:00', 'wpłata'),
(900, 2773.37, '2023-10-11 00:00:00', 'wypłata'),
(474, 1827.67, '2025-04-08 00:00:00', 'wypłata'),
(416, 1966.68, '2023-08-26 00:00:00', 'wpłata'),
(957, 314.65, '2025-12-30 00:00:00', 'wypłata'),
(167, 3869.82, '2023-09-26 00:00:00', 'wypłata'),
(895, 731.69, '2024-02-29 00:00:00', 'wypłata'),
(29, 3078.69, '2025-03-21 00:00:00', 'wpłata'),
(192, 3327.45, '2024-10-17 00:00:00', 'wypłata'),
(474, 3042.66, '2024-05-08 00:00:00', 'wypłata'),
(563, 3935.5, '2023-06-09 00:00:00', 'wypłata'),
(674, 4317.3, '2023-08-25 00:00:00', 'wypłata'),
(616, 1289.88, '2023-03-07 00:00:00', 'wypłata'),
(641, 872.34, '2024-06-14 00:00:00', 'wypłata'),
(102, 2840.8, '2023-08-07 00:00:00', 'wpłata'),
(888, 4054.7, '2025-03-01 00:00:00', 'wpłata'),
(534, 4818.12, '2024-03-10 00:00:00', 'wpłata'),
(75, 4470.56, '2025-11-26 00:00:00', 'wpłata'),
(85, 3769.34, '2025-05-22 00:00:00', 'wypłata'),
(674, 1293.03, '2023-06-06 00:00:00', 'wpłata'),
(495, 209.03, '2025-03-20 00:00:00', 'wpłata'),
(16, 2604.93, '2024-03-09 00:00:00', 'wypłata'),
(793, 1489.8, '2023-11-20 00:00:00', 'wpłata'),
(513, 2951.51, '2024-12-14 00:00:00', 'wpłata'),
(818, 3321.09, '2025-07-16 00:00:00', 'wypłata'),
(874, 712.54, '2024-06-25 00:00:00', 'wypłata'),
(66, 1103.91, '2025-08-20 00:00:00', 'wypłata'),
(861, 4339.98, '2023-02-26 00:00:00', 'wpłata'),
(257, 4581.82, '2025-01-27 00:00:00', 'wpłata'),
(982, 3552.63, '2023-08-18 00:00:00', 'wypłata'),
(920, 98.93, '2025-08-12 00:00:00', 'wpłata'),
(114, 1304.42, '2025-06-08 00:00:00', 'wpłata'),
(139, 4491.82, '2024-04-17 00:00:00', 'wpłata'),
(144, 1719.35, '2023-10-17 00:00:00', 'wpłata'),
(194, 4853.93, '2025-12-28 00:00:00', 'wypłata'),
(512, 821.47, '2024-02-01 00:00:00', 'wypłata'),
(633, 3243.88, '2024-11-14 00:00:00', 'wypłata'),
(670, 1345.45, '2025-07-06 00:00:00', 'wpłata'),
(235, 728.11, '2023-04-15 00:00:00', 'wpłata'),
(563, 2864.65, '2024-07-11 00:00:00', 'wpłata'),
(153, 208.58, '2023-02-26 00:00:00', 'wpłata'),
(902, 3764.47, '2023-08-06 00:00:00', 'wypłata'),
(605, 3436.72, '2025-11-19 00:00:00', 'wpłata'),
(605, 4799.49, '2023-12-05 00:00:00', 'wpłata'),
(494, 1622.84, '2025-05-11 00:00:00', 'wpłata'),
(357, 1389.27, '2024-08-30 00:00:00', 'wypłata'),
(785, 3899.88, '2025-05-12 00:00:00', 'wypłata'),
(682, 1158.05, '2024-02-19 00:00:00', 'wypłata'),
(890, 4935.78, '2023-03-27 00:00:00', 'wypłata'),
(830, 4430.72, '2023-04-02 00:00:00', 'wypłata'),
(180, 2128.92, '2023-05-11 00:00:00', 'wpłata'),
(609, 1027.05, '2025-06-24 00:00:00', 'wypłata'),
(928, 2374.53, '2023-05-19 00:00:00', 'wpłata'),
(490, 2793.44, '2024-06-30 00:00:00', 'wpłata'),
(702, 3741.26, '2025-03-26 00:00:00', 'wypłata'),
(866, 1553.2, '2025-01-02 00:00:00', 'wypłata'),
(585, 467.31, '2023-04-07 00:00:00', 'wpłata'),
(175, 3540.22, '2025-03-13 00:00:00', 'wpłata'),
(586, 1180.2, '2024-05-20 00:00:00', 'wypłata'),
(398, 1114.11, '2025-05-24 00:00:00', 'wpłata'),
(719, 682.66, '2024-04-07 00:00:00', 'wypłata'),
(910, 3079.6, '2024-09-27 00:00:00', 'wpłata'),
(792, 4786.07, '2025-10-12 00:00:00', 'wypłata'),
(632, 3839.58, '2023-01-06 00:00:00', 'wypłata'),
(169, 533.88, '2023-06-22 00:00:00', 'wpłata'),
(227, 1747.51, '2025-04-21 00:00:00', 'wpłata'),
(410, 4486.88, '2023-06-10 00:00:00', 'wpłata'),
(210, 4365.17, '2025-09-25 00:00:00', 'wypłata'),
(231, 2284.59, '2025-09-03 00:00:00', 'wypłata'),
(959, 4139.42, '2024-06-14 00:00:00', 'wypłata'),
(878, 3457.82, '2025-06-21 00:00:00', 'wypłata'),
(757, 2178.81, '2024-05-09 00:00:00', 'wypłata'),
(94, 1942.43, '2024-11-16 00:00:00', 'wpłata'),
(282, 1348.52, '2024-10-19 00:00:00', 'wpłata'),
(220, 3803.0, '2024-07-08 00:00:00', 'wpłata'),
(208, 4511.35, '2024-04-27 00:00:00', 'wypłata'),
(753, 4409.16, '2023-05-08 00:00:00', 'wpłata'),
(606, 3111.08, '2024-01-18 00:00:00', 'wpłata'),
(445, 3553.32, '2023-01-22 00:00:00', 'wpłata'),
(296, 2607.56, '2023-06-17 00:00:00', 'wpłata'),
(840, 250.49, '2024-10-21 00:00:00', 'wypłata'),
(519, 3264.68, '2025-09-29 00:00:00', 'wypłata'),
(896, 1635.68, '2024-03-01 00:00:00', 'wpłata'),
(400, 2309.57, '2025-01-17 00:00:00', 'wpłata'),
(685, 3271.0, '2025-09-09 00:00:00', 'wpłata'),
(888, 1810.32, '2024-11-24 00:00:00', 'wypłata'),
(653, 3652.68, '2024-08-26 00:00:00', 'wpłata'),
(981, 3730.5, '2025-09-02 00:00:00', 'wypłata'),
(57, 3352.18, '2024-01-15 00:00:00', 'wypłata'),
(771, 2605.61, '2025-08-14 00:00:00', 'wypłata'),
(678, 3817.72, '2025-12-19 00:00:00', 'wypłata'),
(280, 3248.36, '2023-01-15 00:00:00', 'wpłata'),
(454, 2860.34, '2024-02-26 00:00:00', 'wpłata'),
(176, 642.28, '2024-04-10 00:00:00', 'wpłata'),
(33, 2295.84, '2023-06-24 00:00:00', 'wpłata'),
(483, 1645.86, '2025-10-18 00:00:00', 'wpłata'),
(815, 1393.02, '2024-07-12 00:00:00', 'wpłata'),
(985, 3766.89, '2023-10-29 00:00:00', 'wpłata'),
(446, 1836.91, '2024-02-16 00:00:00', 'wpłata'),
(566, 4229.25, '2025-09-17 00:00:00', 'wpłata'),
(756, 3271.26, '2024-04-14 00:00:00', 'wypłata'),
(259, 3436.78, '2023-05-16 00:00:00', 'wpłata'),
(357, 2025.77, '2023-04-29 00:00:00', 'wypłata'),
(579, 634.81, '2023-02-18 00:00:00', 'wpłata'),
(578, 2777.94, '2025-06-15 00:00:00', 'wypłata'),
(16, 2345.74, '2024-02-08 00:00:00', 'wypłata'),
(466, 442.66, '2025-05-08 00:00:00', 'wypłata'),
(148, 236.53, '2025-03-28 00:00:00', 'wypłata'),
(444, 521.1, '2023-10-12 00:00:00', 'wpłata'),
(224, 2522.99, '2025-06-02 00:00:00', 'wpłata'),
(921, 2946.19, '2023-11-04 00:00:00', 'wpłata'),
(135, 1398.17, '2025-08-10 00:00:00', 'wpłata'),
(571, 3614.69, '2024-08-24 00:00:00', 'wpłata'),
(390, 4729.58, '2023-10-28 00:00:00', 'wpłata'),
(37, 2616.34, '2025-08-26 00:00:00', 'wypłata'),
(520, 1972.03, '2025-03-07 00:00:00', 'wpłata'),
(421, 114.69, '2025-12-08 00:00:00', 'wypłata'),
(950, 4285.36, '2023-12-20 00:00:00', 'wypłata'),
(768, 4712.9, '2024-04-02 00:00:00', 'wpłata'),
(44, 3425.53, '2023-01-01 00:00:00', 'wypłata'),
(409, 2896.79, '2024-11-28 00:00:00', 'wypłata'),
(466, 78.69, '2024-04-14 00:00:00', 'wpłata'),
(716, 4219.18, '2023-05-22 00:00:00', 'wypłata'),
(616, 4589.71, '2023-09-24 00:00:00', 'wypłata'),
(521, 2080.72, '2024-03-08 00:00:00', 'wpłata'),
(150, 2259.17, '2023-10-18 00:00:00', 'wypłata'),
(229, 1500.96, '2025-10-29 00:00:00', 'wpłata'),
(767, 2554.97, '2024-08-11 00:00:00', 'wypłata'),
(110, 3563.55, '2025-12-24 00:00:00', 'wpłata'),
(572, 2706.18, '2024-05-09 00:00:00', 'wypłata'),
(735, 3591.3, '2024-05-11 00:00:00', 'wpłata'),
(919, 2795.62, '2023-03-11 00:00:00', 'wpłata'),
(124, 4930.81, '2024-06-09 00:00:00', 'wypłata'),
(463, 1979.58, '2023-03-03 00:00:00', 'wypłata'),
(508, 1269.5, '2023-11-08 00:00:00', 'wpłata'),
(268, 1616.77, '2023-02-11 00:00:00', 'wypłata'),
(134, 4459.02, '2024-05-13 00:00:00', 'wpłata'),
(521, 300.71, '2024-09-13 00:00:00', 'wypłata'),
(342, 2708.15, '2023-08-08 00:00:00', 'wpłata'),
(686, 4942.88, '2023-08-17 00:00:00', 'wpłata'),
(768, 4496.58, '2024-02-04 00:00:00', 'wypłata'),
(862, 4498.52, '2023-09-26 00:00:00', 'wypłata'),
(504, 3709.13, '2023-12-21 00:00:00', 'wpłata'),
(341, 2347.37, '2024-12-19 00:00:00', 'wypłata'),
(422, 3376.25, '2024-07-13 00:00:00', 'wypłata'),
(598, 1645.75, '2024-11-26 00:00:00', 'wypłata'),
(271, 2365.91, '2024-08-27 00:00:00', 'wpłata'),
(207, 2111.44, '2024-02-16 00:00:00', 'wypłata'),
(362, 478.11, '2023-07-06 00:00:00', 'wypłata'),
(201, 3154.88, '2023-04-01 00:00:00', 'wypłata'),
(548, 658.03, '2024-12-31 00:00:00', 'wpłata'),
(61, 1997.34, '2023-06-19 00:00:00', 'wpłata'),
(496, 2530.98, '2025-06-05 00:00:00', 'wpłata'),
(672, 775.67, '2024-09-26 00:00:00', 'wpłata'),
(330, 2674.04, '2024-05-19 00:00:00', 'wypłata'),
(9, 1972.09, '2025-07-26 00:00:00', 'wypłata'),
(879, 4968.83, '2024-09-19 00:00:00', 'wpłata'),
(97, 4983.87, '2024-04-21 00:00:00', 'wypłata'),
(369, 424.74, '2024-02-23 00:00:00', 'wpłata'),
(305, 1292.27, '2025-08-09 00:00:00', 'wpłata'),
(545, 1733.44, '2023-07-29 00:00:00', 'wypłata'),
(828, 2612.38, '2025-05-17 00:00:00', 'wpłata'),
(753, 1825.87, '2025-04-05 00:00:00', 'wypłata'),
(340, 3385.59, '2024-11-28 00:00:00', 'wpłata'),
(93, 124.94, '2024-04-20 00:00:00', 'wypłata'),
(515, 4701.29, '2023-10-19 00:00:00', 'wypłata'),
(707, 3596.82, '2023-10-21 00:00:00', 'wpłata'),
(983, 2490.77, '2024-09-09 00:00:00', 'wpłata'),
(571, 3733.01, '2023-10-26 00:00:00', 'wpłata'),
(517, 1850.23, '2023-09-19 00:00:00', 'wpłata'),
(179, 3070.62, '2023-12-05 00:00:00', 'wpłata'),
(266, 2220.03, '2024-01-01 00:00:00', 'wpłata'),
(774, 277.72, '2023-03-01 00:00:00', 'wpłata'),
(907, 4772.25, '2025-04-02 00:00:00', 'wpłata'),
(411, 965.83, '2025-05-17 00:00:00', 'wypłata'),
(992, 3376.67, '2025-09-18 00:00:00', 'wypłata'),
(237, 1806.14, '2023-03-11 00:00:00', 'wypłata'),
(928, 1603.89, '2023-08-24 00:00:00', 'wpłata'),
(299, 3258.98, '2024-07-12 00:00:00', 'wpłata'),
(141, 2876.59, '2024-08-18 00:00:00', 'wypłata'),
(32, 1917.73, '2023-12-18 00:00:00', 'wypłata'),
(283, 1547.1, '2023-03-04 00:00:00', 'wypłata'),
(149, 3289.91, '2023-09-16 00:00:00', 'wpłata'),
(159, 1060.42, '2025-01-14 00:00:00', 'wpłata'),
(814, 3059.54, '2023-02-15 00:00:00', 'wypłata'),
(464, 2925.93, '2023-04-06 00:00:00', 'wpłata'),
(154, 2724.8, '2024-03-04 00:00:00', 'wpłata'),
(809, 3099.03, '2023-11-05 00:00:00', 'wypłata'),
(691, 891.63, '2025-10-20 00:00:00', 'wypłata'),
(212, 4096.88, '2023-02-04 00:00:00', 'wpłata'),
(161, 676.04, '2025-12-23 00:00:00', 'wpłata'),
(134, 1678.39, '2024-11-15 00:00:00', 'wypłata'),
(626, 1774.57, '2023-11-10 00:00:00', 'wypłata'),
(573, 1635.27, '2024-09-16 00:00:00', 'wypłata'),
(366, 3181.14, '2024-08-14 00:00:00', 'wpłata'),
(223, 783.58, '2023-06-13 00:00:00', 'wpłata'),
(460, 2836.72, '2023-04-29 00:00:00', 'wpłata'),
(558, 3673.82, '2023-01-09 00:00:00', 'wpłata'),
(943, 4326.73, '2023-02-12 00:00:00', 'wpłata'),
(476, 4199.4, '2023-01-15 00:00:00', 'wypłata'),
(632, 2082.29, '2025-08-22 00:00:00', 'wpłata'),
(229, 2317.26, '2024-12-23 00:00:00', 'wpłata'),
(627, 4140.14, '2025-01-28 00:00:00', 'wypłata'),
(151, 3352.82, '2025-12-09 00:00:00', 'wypłata'),
(889, 4712.29, '2025-04-27 00:00:00', 'wpłata'),
(333, 839.45, '2024-05-17 00:00:00', 'wpłata'),
(241, 616.17, '2023-03-06 00:00:00', 'wypłata'),
(818, 3738.0, '2024-08-30 00:00:00', 'wypłata'),
(115, 1926.99, '2023-03-20 00:00:00', 'wpłata'),
(35, 3204.67, '2024-12-27 00:00:00', 'wpłata'),
(652, 217.92, '2025-04-09 00:00:00', 'wypłata'),
(346, 2335.46, '2025-07-25 00:00:00', 'wpłata'),
(275, 3986.36, '2025-12-10 00:00:00', 'wpłata'),
(868, 4427.6, '2025-01-10 00:00:00', 'wypłata'),
(680, 2864.1, '2023-12-11 00:00:00', 'wpłata'),
(540, 3247.11, '2023-10-09 00:00:00', 'wpłata'),
(354, 469.56, '2023-02-15 00:00:00', 'wpłata'),
(737, 426.36, '2023-02-13 00:00:00', 'wpłata'),
(911, 1105.1, '2025-04-21 00:00:00', 'wpłata'),
(268, 4593.93, '2023-08-26 00:00:00', 'wpłata'),
(880, 3943.99, '2023-06-08 00:00:00', 'wpłata'),
(729, 3274.34, '2023-11-10 00:00:00', 'wypłata'),
(535, 299.7, '2025-08-20 00:00:00', 'wypłata'),
(415, 4949.38, '2025-02-09 00:00:00', 'wypłata'),
(986, 3961.73, '2023-07-21 00:00:00', 'wypłata'),
(608, 1213.54, '2025-02-16 00:00:00', 'wpłata'),
(532, 4869.56, '2024-11-19 00:00:00', 'wpłata'),
(478, 4244.34, '2024-08-03 00:00:00', 'wypłata'),
(122, 4651.55, '2023-09-29 00:00:00', 'wypłata'),
(424, 1748.84, '2025-10-29 00:00:00', 'wpłata'),
(457, 766.01, '2024-10-19 00:00:00', 'wpłata');



	ALTER TABLE transakcje MODIFY id_transakcji INT DEFAULT (NEXTVAL(transakcje_seq));



/*profil internetowy*/
    INSERT INTO profil_internetowy (id_klienta)
SELECT id_klienta FROM Klienci;

UPDATE profil_internetowy p
JOIN Klienci k ON p.id_klienta = k.id_klienta
SET 
    p.login = left(CONCAT(LOWER(k.imie), '_', LOWER(k.nazwisko), '_' , k.id_klienta ), 50),
    p.haslo_hash = SUBSTRING(MD5(RAND()), 1, 10);
    
    
    
/*banki*/
INSERT INTO banki (nazwa_banku, czas_otwarcia, czas_zamkniecia, otwarte_codziennie) 
VALUES
('PKO BP', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('Bank Millennium', '2025-01-01 09:00:00', '2025-01-01 17:00:00', FALSE),
('Alior Bank', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('ING Bank Śląski', '2025-01-01 09:00:00', '2025-01-01 17:00:00', FALSE),
('Santander Bank', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('mBank', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('Bank Pekao', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('Bank Zachodni WBK', '2025-01-01 09:00:00', '2025-01-01 17:00:00', FALSE),
('Citi Handlowy', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE),
('Credit Agricole', '2025-01-01 09:00:00', '2025-01-01 17:00:00', TRUE);






INSERT INTO lokalizacje (adres, miasto, kod_pocztowy, latitude, longitude) 
VALUES
('ul. Złota 11', 'Warszawa', '00-100', 52.2298, 21.0118),
('ul. Jana Pawła II 12', 'Warszawa', '00-200', 52.2290, 21.0120),
('ul. Pięciomorgowa 3', 'Kraków', '30-300', 50.0619, 19.9383),
('ul. Nowa 7', 'Gdańsk', '80-400', 54.3520, 18.6466),
('ul. Słoneczna 5', 'Wrocław', '50-500', 51.1079, 17.0385),
('ul. Wolności 2', 'Poznań', '60-600', 52.4084, 16.9342),
('ul. Zwycięstwa 8', 'Łódź', '90-700', 51.7592, 19.4560),
('ul. Mickiewicza 4', 'Katowice', '40-800', 50.2649, 19.0237),
('ul. Kwiatowa 9', 'Lublin', '20-900', 51.2465, 22.5684),
('ul. Młodszych 6', 'Szczecin', '70-100', 53.4289, 14.5530);

INSERT INTO banki_lokalizacje (id_banku, id_lokalizacji) 
VALUES
(1, 1), 
(1,2),
(2, 2),  
(3, 3), 
(4, 4), 
(4,5),
(5, 5), 
(5,8), 
(6, 6), 
(7, 7),  
(8, 8), 
(9, 9), 
(10, 10); 

/*pracownicy*/
INSERT INTO pracownicy (id_banku, imie, nazwisko, stanowisko, telefon, poczatek_stazu, pensja) 
VALUES
(1, 'Anna', 'Kowalska', 'Kierownik', '123-456-789', '2023-01-15', 5500.00),
(1, 'Piotr', 'Nowak', 'Kasjer', '123-456-790', '2022-11-01', 3800.00),
(1, 'Marek', 'Wiśniewski', 'Doradca Klienta', '123-456-791', '2021-06-10', 4500.00),
(1, 'Katarzyna', 'Zielińska', 'Menedżer', '123-456-792', '2020-08-22', 6000.00),

(2, 'Jakub', 'Wójcik', 'Kierownik', '123-456-793', '2022-02-17', 5300.00),
(2, 'Ewa', 'Kowalczyk', 'Kasjer', '123-456-794', '2023-03-05', 3700.00),
(2, 'Tomasz', 'Bąk', 'Doradca Klienta', '123-456-795', '2021-09-09', 4600.00),
(2, 'Agata', 'Sikora', 'Menedżer', '123-456-796', '2020-11-19', 6200.00),

(3, 'Zuzanna', 'Kaczmarek', 'Kierownik', '123-456-797', '2023-01-10', 5500.00),
(3, 'Michał', 'Mazur', 'Kasjer', '123-456-798', '2022-06-18', 3800.00),
(3, 'Kamil', 'Jankowski', 'Doradca Klienta', '123-456-799', '2021-07-11', 4500.00),
(3, 'Monika', 'Lewandowska', 'Menedżer', '123-456-800', '2020-12-05', 6000.00),

(4, 'Jan', 'Witkowski', 'Kierownik', '123-456-801', '2021-04-10', 5300.00),
(4, 'Agnieszka', 'Górska', 'Kasjer', '123-456-802', '2023-01-22', 3700.00),
(4, 'Patryk', 'Rogowski', 'Doradca Klienta', '123-456-803', '2022-05-08', 4600.00),
(4, 'Julia', 'Pawlowska', 'Menedżer', '123-456-804', '2020-10-13', 6200.00),

(1, 'Aleksandra', 'Woźniak', 'Kierownik', '123-456-805', '2023-03-25', 5500.00),
(1, 'Bartosz', 'Michałowski', 'Kasjer', '123-456-806', '2021-10-04', 3800.00),
(1, 'Weronika', 'Stolarz', 'Doradca Klienta', '123-456-807', '2022-12-01', 4500.00),
(1, 'Jakub', 'Zawisza', 'Menedżer', '123-456-808', '2020-07-18', 6000.00),

(2, 'Szymon', 'Dąbrowski', 'Kierownik', '123-456-809', '2021-02-03', 5300.00),
(2, 'Izabela', 'Tracz', 'Kasjer', '123-456-810', '2023-05-19', 3700.00),
(2, 'Oskar', 'Duda', 'Doradca Klienta', '123-456-811', '2022-04-17', 4600.00),
(2, 'Martyna', 'Kwiatkowska', 'Menedżer', '123-456-812', '2020-09-20', 6200.00),

(3, 'Emilia', 'Kowalik', 'Kierownik', '123-456-813', '2022-12-12', 5500.00),
(3, 'Karol', 'Żuraw', 'Kasjer', '123-456-814', '2021-08-15', 3800.00),
(3, 'Paulina', 'Sienkiewicz', 'Doradca Klienta', '123-456-815', '2020-11-30', 4500.00),

(3, 'Damian', 'Mazurek', 'Menedżer', '123-456-816', '2019-05-25', 6000.00),
(4, 'Rafał', 'Markowski', 'Kierownik', '123-456-817', '2022-07-29', 5300.00),
(4, 'Kinga', 'Białek', 'Kasjer', '123-456-818', '2021-03-19', 3700.00),
(4, 'Monika', 'Kaczmarek', 'Doradca Klienta', '123-456-819', '2020-04-13', 4600.00),
(4, 'Krzysztof', 'Walczak', 'Menedżer', '123-456-820', '2019-11-14', 6200.00),

(5, 'Paweł', 'Sadowski', 'Kierownik', '456-789-016', '2022-08-01', 5400.00),
(5, 'Joanna', 'Wesołowska', 'Kasjer Bankowy', '456-789-017', '2021-05-15', 3800.00),
(5, 'Mateusz', 'Baran', 'Doradca Klienta', '456-789-018', '2020-06-10', 4700.00),
(5, 'Ewelina', 'Król', 'Menedżer', '456-789-019', '2019-09-25', 6300.00),

(6, 'Adam', 'Sobczak', 'Kierownik', '456-789-020', '2021-03-11', 5500.00),
(6, 'Karolina', 'Adamczyk', 'Kasjer Bankowy', '456-789-021', '2022-07-21', 3750.00),
(6, 'Grzegorz', 'Lis', 'Doradca Klienta', '456-789-022', '2020-04-19', 4600.00),
(6, 'Beata', 'Nowicka', 'Menedżer', '456-789-023', '2018-12-12', 6400.00),

(7, 'Michał', 'Kozłowski', 'Kierownik', '456-789-024', '2021-07-05', 5400.00),
(7, 'Izabela', 'Czarnecka', 'Kasjer Bankowy', '456-789-025', '2023-01-29', 3650.00),
(7, 'Patrycja', 'Zawada', 'Doradca Klienta', '456-789-026', '2021-11-17', 4550.00),
(7, 'Łukasz', 'Marek', 'Menedżer', '456-789-027', '2019-06-08', 6150.00),

(8, 'Tomasz', 'Rybak', 'Kierownik', '456-789-028', '2020-10-10', 5600.00),
(8, 'Monika', 'Kubiak', 'Kasjer Bankowy', '456-789-029', '2022-05-13', 3700.00),
(8, 'Sebastian', 'Krupa', 'Doradca Klienta', '456-789-030', '2021-08-22', 4700.00),
(8, 'Zofia', 'Urban', 'Menedżer', '456-789-031', '2019-04-01', 6250.00),

(9, 'Radosław', 'Bielecki', 'Kierownik', '456-789-032', '2021-02-20', 5500.00),
(9, 'Agnieszka', 'Lech', 'Kasjer Bankowy', '456-789-033', '2023-02-12', 3800.00),
(9, 'Krzysztof', 'Maj', 'Doradca Klienta', '456-789-034', '2022-09-30', 4600.00),
(9, 'Barbara', 'Rutkowska', 'Menedżer', '456-789-035', '2018-11-15', 6350.00),

(10, 'Damian', 'Orłowski', 'Kierownik', '456-789-036', '2022-04-03', 5600.00),
(10, 'Julia', 'Michalska', 'Kasjer Bankowy', '456-789-037', '2023-06-07', 3700.00),
(10, 'Andrzej', 'Grzelak', 'Doradca Klienta', '456-789-038', '2021-12-20', 4800.00),
(10, 'Emilia', 'Domańska', 'Menedżer', '456-789-039', '2019-07-28', 6300.00);




INSERT INTO klienci_pracownicy (id_pracownika, id_klienta) VALUES
(28, 216),
(29, 786),
(49, 569),
(9, 265),
(28, 676),
(10, 248),
(38, 866),
(9, 351),
(27, 293),
(25, 223),
(20, 508),
(4, 18),
(28, 995),
(7, 957),
(27, 585),
(18, 675),
(2, 226),
(14, 73),
(4, 544),
(54, 845),
(53, 27),
(5, 797),
(13, 835),
(52, 705),
(37, 1),
(30, 260),
(25, 393),
(31, 496),
(35, 778),
(8, 972),
(15, 932),
(42, 557),
(50, 658),
(11, 676),
(2, 126),
(40, 195),
(17, 943),
(26, 24),
(24, 481),
(26, 694),
(12, 520),
(30, 87),
(34, 347),
(11, 815),
(42, 158),
(41, 430),
(44, 602),
(13, 669),
(17, 122),
(31, 527),
(7, 960),
(53, 27),
(13, 90),
(53, 692),
(42, 344),
(48, 357),
(29, 668),
(6, 961),
(25, 805),
(13, 611),
(23, 757),
(44, 379),
(34, 68),
(33, 246),
(50, 598),
(53, 89),
(21, 918),
(45, 540),
(19, 66),
(17, 63),
(48, 901),
(48, 422),
(20, 533),
(33, 371),
(41, 722),
(18, 168),
(53, 920),
(33, 335),
(49, 695),
(7, 13),
(46, 369),
(22, 541),
(17, 367),
(46, 180),
(33, 500),
(29, 626),
(41, 209),
(11, 716),
(44, 576),
(46, 890),
(40, 600),
(8, 682),
(55, 141),
(22, 180),
(51, 354),
(40, 851),
(35, 566),
(11, 670),
(33, 920),
(32, 18),
(34, 883),
(32, 668),
(6, 539),
(47, 424),
(34, 62),
(25, 257),
(36, 498),
(33, 629),
(44, 401),
(15, 492),
(4, 599),
(4, 18),
(26, 223),
(36, 787),
(3, 684),
(20, 407),
(53, 341),
(2, 532),
(39, 380),
(11, 938),
(5, 809),
(26, 629),
(26, 9),
(30, 354),
(11, 567),
(49, 954),
(24, 393),
(47, 688),
(47, 160),
(23, 203),
(8, 21),
(13, 595),
(9, 42),
(9, 187),
(55, 776),
(10, 67),
(46, 206),
(48, 233),
(19, 587),
(40, 653),
(33, 258),
(47, 755),
(19, 380),
(11, 270),
(26, 763),
(39, 380),
(42, 376),
(43, 857),
(23, 620),
(5, 350),
(15, 688),
(11, 85),
(5, 893),
(42, 277),
(4, 341),
(40, 611),
(39, 159),
(15, 719),
(14, 956),
(31, 764),
(15, 532),
(26, 653),
(43, 902),
(6, 239),
(50, 249),
(26, 751),
(52, 159),
(49, 333),
(38, 427),
(7, 415),
(19, 674),
(42, 887),
(28, 207),
(4, 28),
(12, 144),
(43, 559),
(26, 707),
(33, 561),
(15, 44),
(22, 324),
(17, 655),
(38, 273),
(26, 698),
(42, 144),
(22, 45),
(21, 23),
(30, 621),
(37, 621),
(25, 392),
(28, 237),
(44, 607),
(41, 779),
(49, 633),
(22, 156),
(10, 508),
(11, 891),
(18, 307),
(21, 573),
(3, 469),
(55, 386),
(24, 466),
(7, 508),
(3, 875),
(5, 258),
(13, 159),
(44, 987),
(11, 339),
(8, 340),
(30, 393),
(43, 521),
(7, 330),
(1, 413),
(20, 999),
(54, 335),
(6, 483),
(8, 966),
(35, 458),
(35, 832),
(29, 898),
(8, 844),
(12, 335),
(17, 467),
(45, 409),
(39, 246),
(2, 861),
(25, 44),
(22, 281),
(47, 36),
(45, 559),
(41, 527),
(3, 478),
(36, 961),
(48, 825),
(46, 360),
(23, 994),
(55, 451),
(48, 122),
(55, 815),
(25, 445),
(33, 567),
(6, 250),
(39, 48),
(52, 992),
(56, 588),
(41, 440),
(21, 924),
(29, 752),
(3, 828),
(45, 534),
(30, 606),
(35, 500),
(47, 886),
(26, 631),
(3, 630),
(9, 254),
(44, 673),
(51, 179),
(7, 76),
(10, 584),
(49, 49),
(50, 98),
(41, 342),
(13, 844),
(47, 703),
(32, 843),
(29, 900),
(47, 664),
(45, 282),
(17, 499),
(48, 768),
(4, 199),
(21, 215),
(50, 645),
(49, 582),
(41, 608),
(51, 42),
(25, 34),
(16, 215),
(11, 993),
(40, 348),
(17, 541),
(3, 758),
(36, 318),
(41, 937),
(49, 394),
(53, 894),
(8, 192),
(12, 41),
(5, 823),
(10, 568),
(31, 682),
(31, 592),
(8, 899),
(20, 581),
(29, 98),
(10, 52),
(46, 290),
(46, 466),
(32, 938),
(49, 23),
(41, 700),
(46, 797),
(43, 656),
(16, 465),
(14, 178),
(54, 454),
(3, 540),
(43, 266),
(37, 924),
(15, 892),
(32, 745),
(51, 537),
(31, 894),
(37, 121),
(42, 962),
(10, 614),
(25, 167),
(14, 30),
(41, 750),
(24, 546),
(12, 573),
(40, 765),
(16, 300),
(3, 931),
(11, 211),
(22, 178),
(28, 752),
(18, 932),
(20, 812),
(21, 337),
(18, 613),
(29, 701),
(52, 374),
(42, 497),
(13, 721),
(25, 919),
(1, 900),
(1, 803),
(29, 494),
(38, 510),
(15, 12),
(35, 815),
(4, 328),
(12, 592),
(40, 812),
(38, 320),
(30, 606),
(39, 948),
(50, 66),
(23, 417),
(3, 145),
(16, 939),
(14, 808),
(7, 541),
(52, 902),
(36, 836),
(18, 681),
(21, 567),
(35, 973),
(46, 656),
(28, 213),
(16, 57),
(25, 108),
(26, 285),
(12, 394),
(50, 806),
(14, 407),
(26, 91),
(55, 323),
(33, 771),
(18, 364),
(30, 619),
(22, 527),
(53, 106),
(12, 559),
(44, 713),
(14, 391),
(16, 203),
(55, 760),
(5, 10),
(1, 785),
(51, 460),
(25, 676),
(18, 173),
(1, 542),
(56, 105),
(45, 527),
(24, 209),
(46, 406),
(2, 473),
(27, 769),
(49, 22),
(17, 382),
(13, 326),
(53, 999),
(55, 598),
(55, 291),
(26, 144),
(47, 954),
(13, 366),
(25, 373),
(34, 952),
(30, 731),
(43, 391),
(8, 769),
(30, 976),
(17, 473),
(12, 959),
(54, 507),
(23, 542),
(24, 426),
(39, 408),
(56, 128),
(29, 786),
(50, 384),
(1, 496),
(30, 855),
(25, 146),
(39, 866),
(15, 155),
(52, 543),
(9, 50),
(41, 790),
(35, 78),
(10, 347),
(35, 836),
(35, 81),
(15, 817),
(9, 563),
(55, 157),
(40, 448),
(12, 320),
(49, 682),
(27, 995),
(37, 856),
(49, 736),
(23, 465),
(54, 38),
(3, 477),
(49, 480),
(30, 702),
(48, 991),
(44, 313),
(43, 894),
(9, 398),
(23, 711),
(44, 761),
(13, 655),
(26, 431),
(44, 35),
(10, 60),
(22, 36),
(42, 603),
(37, 654),
(39, 529),
(19, 786),
(52, 166),
(16, 305),
(36, 788),
(50, 763),
(18, 16),
(50, 772),
(50, 691),
(22, 191),
(49, 993),
(41, 245),
(1, 847),
(5, 655),
(23, 525),
(31, 740),
(4, 326),
(12, 678),
(28, 259),
(42, 627),
(44, 472),
(51, 86),
(40, 153),
(50, 728),
(31, 726),
(25, 38),
(45, 186),
(29, 661),
(3, 705),
(35, 246),
(49, 942),
(52, 130),
(36, 969),
(3, 551),
(6, 686),
(29, 375),
(30, 100),
(51, 648),
(37, 605),
(50, 41),
(54, 724),
(35, 405),
(17, 678),
(55, 445),
(38, 552),
(24, 136),
(44, 228),
(25, 101),
(40, 518),
(54, 680),
(6, 405),
(22, 491),
(18, 524),
(40, 319),
(27, 514),
(33, 803),
(26, 810),
(39, 622),
(14, 565),
(26, 665),
(21, 283),
(21, 5),
(55, 110),
(26, 413),
(34, 92),
(8, 469),
(27, 640),
(11, 387),
(24, 480),
(11, 169),
(28, 678),
(41, 467),
(36, 179),
(21, 351),
(23, 975),
(11, 828),
(49, 14),
(56, 747),
(53, 445),
(7, 278),
(26, 974),
(11, 440),
(4, 56),
(42, 903),
(44, 562),
(46, 492),
(7, 798),
(56, 37),
(39, 302),
(10, 536),
(20, 156),
(30, 95),
(22, 562),
(48, 87),
(29, 179),
(42, 691),
(12, 187),
(10, 113),
(38, 956),
(42, 759),
(16, 245),
(50, 770),
(50, 540),
(25, 21),
(20, 58),
(39, 261),
(56, 835),
(32, 964),
(18, 275),
(6, 64),
(22, 271),
(2, 3),
(7, 441),
(40, 797),
(22, 578),
(10, 257),
(20, 680),
(5, 54),
(34, 315),
(21, 738),
(16, 196),
(55, 93),
(8, 366),
(3, 264),
(54, 649),
(28, 262),
(49, 67),
(33, 15),
(50, 504),
(56, 520),
(32, 360),
(9, 977),
(36, 593),
(50, 464),
(32, 640),
(11, 229),
(28, 291),
(14, 545),
(30, 957),
(19, 130),
(8, 914),
(56, 445),
(43, 394),
(17, 283),
(12, 536),
(39, 85),
(48, 141),
(19, 111),
(33, 144),
(45, 849),
(37, 912),
(41, 388),
(20, 329),
(45, 323),
(44, 296),
(39, 76),
(39, 222),
(55, 861),
(30, 795),
(36, 33),
(17, 320),
(33, 913),
(50, 265),
(10, 177),
(40, 933),
(41, 487),
(45, 592),
(6, 131),
(7, 2),
(4, 913),
(8, 793),
(37, 816),
(56, 785),
(34, 911),
(22, 553),
(5, 37),
(18, 339),
(48, 890),
(36, 230),
(16, 20),
(26, 539),
(29, 373),
(6, 213),
(12, 347),
(54, 54),
(3, 82),
(25, 867),
(50, 483),
(23, 453),
(11, 484),
(8, 57),
(37, 831),
(1, 205),
(50, 376),
(53, 444),
(55, 945),
(33, 150),
(19, 235),
(2, 112),
(5, 976),
(12, 223),
(3, 863),
(23, 657),
(34, 905),
(2, 519),
(6, 717),
(30, 88),
(53, 415),
(44, 582),
(23, 906),
(48, 510),
(28, 770),
(35, 656),
(45, 539),
(48, 14),
(48, 680),
(27, 363),
(4, 850),
(34, 511),
(30, 766),
(44, 871),
(27, 909),
(38, 484),
(8, 313),
(36, 642),
(14, 486),
(18, 984),
(25, 340),
(15, 389),
(18, 635),
(38, 430),
(34, 725),
(39, 894),
(3, 677),
(18, 24),
(39, 708),
(37, 829),
(49, 729),
(53, 161),
(3, 639),
(22, 527),
(4, 319),
(38, 266),
(6, 783),
(54, 987),
(30, 432),
(30, 289),
(33, 711),
(32, 809),
(2, 986),
(42, 609),
(30, 128),
(2, 280),
(25, 364),
(33, 441),
(7, 295),
(4, 917),
(14, 738),
(27, 382),
(32, 155),
(31, 71),
(40, 453),
(12, 314),
(19, 49),
(15, 521),
(23, 158),
(8, 136),
(3, 475),
(12, 303),
(15, 123),
(56, 300),
(28, 818),
(30, 275),
(25, 892),
(45, 293),
(47, 726),
(34, 979),
(27, 863),
(22, 462),
(13, 160),
(25, 610),
(16, 233),
(48, 44),
(39, 824),
(41, 290),
(16, 498),
(22, 748),
(19, 413),
(39, 273),
(37, 394),
(3, 501),
(31, 643),
(36, 331),
(20, 337),
(17, 382),
(11, 703),
(25, 918),
(15, 56),
(15, 392),
(45, 60),
(33, 186),
(10, 293),
(27, 776),
(31, 895),
(3, 673),
(7, 764),
(42, 130),
(18, 302),
(32, 166),
(24, 560),
(50, 568),
(7, 277),
(19, 500),
(2, 769),
(56, 170),
(3, 546),
(40, 376),
(46, 533),
(4, 638),
(45, 3),
(2, 727),
(45, 40),
(48, 324),
(44, 384),
(20, 266),
(10, 99),
(33, 963),
(54, 990),
(17, 771),
(38, 937),
(11, 237),
(45, 84),
(24, 796),
(24, 179),
(31, 730),
(22, 624),
(49, 365),
(21, 208),
(37, 337),
(36, 445),
(45, 512),
(30, 717),
(17, 326),
(41, 204),
(54, 857),
(8, 308),
(16, 253),
(46, 691),
(37, 760),
(16, 527),
(6, 54),
(7, 921),
(38, 736),
(4, 361),
(35, 481),
(41, 365),
(1, 596),
(18, 543),
(46, 137),
(16, 877),
(37, 522),
(40, 17),
(14, 803),
(7, 395),
(25, 730),
(37, 624),
(11, 820),
(52, 854),
(36, 137),
(32, 731),
(45, 116),
(26, 193),
(28, 742),
(16, 558),
(53, 213),
(9, 995),
(23, 223),
(26, 664),
(20, 76),
(37, 719),
(19, 281),
(11, 175),
(2, 234),
(23, 7),
(44, 717),
(37, 617),
(49, 394),
(14, 351),
(43, 133),
(21, 269),
(13, 124),
(19, 319),
(32, 831),
(17, 198),
(28, 742),
(20, 765),
(33, 171),
(37, 623),
(17, 593),
(17, 401),
(24, 777),
(28, 530),
(4, 381),
(31, 377),
(12, 278),
(41, 922),
(19, 197),
(24, 539),
(7, 605),
(51, 258),
(46, 495),
(6, 586),
(51, 200),
(23, 165),
(8, 606),
(54, 976),
(27, 401),
(24, 848),
(33, 870),
(20, 137),
(50, 342),
(5, 445),
(51, 962),
(14, 35),
(42, 195),
(54, 549),
(12, 51),
(27, 915),
(8, 255),
(24, 412),
(47, 145),
(40, 878),
(5, 39),
(19, 803),
(20, 346),
(28, 441),
(7, 7),
(24, 548),
(40, 444),
(43, 706),
(14, 392),
(55, 312),
(8, 155),
(4, 570),
(53, 156),
(5, 755),
(14, 535),
(2, 742),
(53, 550),
(14, 643),
(10, 955),
(9, 522),
(20, 776),
(30, 437),
(23, 348),
(30, 922),
(47, 446),
(25, 634),
(56, 973),
(42, 244),
(48, 959),
(30, 130),
(14, 44),
(15, 796),
(23, 968),
(54, 780),
(27, 988),
(46, 728),
(17, 252),
(56, 817),
(28, 585),
(10, 548),
(55, 727),
(16, 130),
(2, 538),
(28, 690),
(41, 326),
(7, 63),
(4, 130),
(32, 851),
(10, 336),
(24, 991),
(1, 184),
(55, 570),
(24, 131),
(5, 175),
(52, 910),
(4, 413),
(32, 714),
(22, 155),
(56, 130),
(47, 727),
(53, 765),
(23, 282),
(1, 345),
(42, 327),
(40, 437),
(50, 340),
(16, 858),
(27, 536),
(16, 155),
(35, 625),
(40, 729),
(1, 454),
(23, 588),
(39, 722),
(15, 757),
(52, 246),
(52, 640),
(18, 964),
(8, 222),
(18, 735),
(47, 433),
(2, 296),
(41, 234),
(12, 349),
(6, 917),
(13, 478),
(8, 205),
(13, 958),
(50, 489),
(8, 389),
(25, 496),
(2, 752),
(49, 126),
(40, 610),
(24, 295),
(43, 466),
(16, 43),
(23, 254),
(19, 301),
(8, 446),
(2, 632),
(33, 292),
(10, 657),
(39, 449),
(52, 752),
(55, 869),
(21, 911),
(47, 972),
(12, 630),
(52, 48),
(9, 759),
(41, 64),
(52, 880),
(33, 444),
(43, 987),
(15, 985),
(1, 506),
(20, 750),
(26, 999),
(5, 189),
(1, 891),
(51, 210),
(22, 893),
(10, 776),
(6, 22),
(30, 526),
(29, 182),
(52, 76),
(35, 575),
(42, 651),
(39, 981),
(4, 823),
(8, 542),
(22, 771),
(26, 416),
(52, 173),
(19, 834),
(41, 325),
(11, 537),
(7, 359),
(38, 212),
(43, 373),
(54, 383),
(30, 668),
(48, 241),
(15, 276),
(56, 42),
(36, 902),
(1, 444),
(41, 914),
(30, 197),
(7, 766),
(6, 259),
(6, 635),
(26, 950),
(6, 581),
(53, 335),
(1, 887),
(55, 697),
(33, 835),
(41, 705),
(20, 224),
(56, 682),
(54, 302),
(37, 330),
(33, 628),
(10, 308),
(37, 794),
(4, 146),
(41, 266),
(53, 319),
(24, 839),
(43, 707),
(13, 215),
(23, 628),
(45, 701),
(45, 979),
(22, 619),
(46, 569),
(6, 960),
(14, 911),
(4, 386),
(43, 884),
(29, 806),
(51, 248),
(13, 517),
(32, 300),
(39, 194),
(31, 909),
(25, 199),
(48, 202),
(50, 113),
(50, 889),
(43, 605),
(4, 697),
(47, 479),
(22, 888),
(21, 818),
(18, 85),
(10, 123),
(56, 133),
(38, 459),
(32, 588),
(12, 246),
(48, 23),
(7, 321),
(7, 400),
(55, 381),
(17, 796),
(38, 780),
(15, 287),
(10, 913),
(50, 781),
(24, 418),
(55, 413),
(50, 581),
(48, 722),
(6, 976),
(32, 738),
(26, 926),
(20, 486),
(16, 736),
(42, 269),
(38, 458),
(7, 567),
(36, 334),
(36, 274),
(45, 776),
(34, 758),
(17, 543),
(30, 275),
(5, 888),
(55, 61),
(8, 317),
(11, 142),
(55, 441),
(35, 300),
(39, 475),
(8, 920),
(1, 76),
(13, 868),
(9, 34),
(55, 772),
(20, 490),
(25, 24),
(39, 471),
(50, 669),
(4, 808),
(50, 613),
(48, 920),
(15, 36),
(36, 56),
(31, 276),
(16, 770),
(18, 506),
(26, 568),
(25, 271),
(15, 221),
(15, 845),
(7, 766),
(18, 465),
(6, 446),
(5, 692),
(35, 614),
(36, 288),
(19, 986),
(11, 531),
(8, 537),
(46, 520),
(33, 705),
(30, 627),
(20, 897),
(53, 175),
(15, 68),
(15, 467),
(6, 426),
(28, 597),
(50, 249),
(1, 392),
(23, 619),
(8, 510),
(3, 911),
(40, 594),
(10, 483),
(44, 155),
(25, 305),
(25, 791),
(8, 222),
(45, 470),
(7, 618),
(11, 25),
(17, 422),
(14, 48),
(25, 488),
(34, 121),
(34, 169),
(2, 866),
(41, 447),
(55, 426),
(27, 156),
(43, 19),
(40, 479),
(47, 129),
(54, 171),
(4, 59),
(12, 472),
(36, 23),
(49, 390),
(14, 416),
(56, 936),
(29, 710),
(4, 18),
(41, 607),
(11, 966),
(36, 167),
(37, 429),
(53, 540),
(7, 578),
(13, 724),
(34, 555),
(15, 817),
(38, 784),
(50, 52),
(26, 554),
(21, 771),
(16, 315),
(31, 451),
(23, 817),
(1, 49),
(41, 547),
(41, 388),
(21, 506),
(8, 368),
(11, 201),
(26, 704),
(36, 493),
(2, 689),
(47, 417),
(52, 433),
(6, 471),
(15, 272),
(2, 679),
(45, 292),
(50, 154),
(2, 84),
(2, 817),
(5, 487),
(21, 337),
(52, 849),
(3, 951),
(24, 524),
(37, 296),
(36, 523),
(24, 626),
(54, 202),
(22, 547),
(50, 703),
(33, 194),
(7, 120),
(48, 347),
(48, 109),
(51, 917),
(19, 980),
(38, 14),
(33, 886),
(31, 708),
(32, 724),
(24, 119),
(41, 944),
(49, 506),
(3, 845),
(41, 778),
(12, 542),
(26, 444),
(53, 668),
(23, 790),
(6, 186),
(15, 661),
(52, 97),
(10, 145),
(55, 626),
(45, 925),
(40, 212),
(52, 635),
(55, 766),
(37, 357),
(1, 295),
(28, 276),
(4, 835),
(37, 611),
(50, 289),
(11, 389),
(52, 516),
(14, 868),
(23, 565),
(23, 573),
(27, 648),
(35, 199),
(16, 951),
(36, 868),
(24, 866),
(38, 582),
(20, 384),
(29, 488),
(40, 157),
(46, 106),
(49, 777),
(13, 580),
(8, 885),
(17, 158),
(52, 621),
(37, 189),
(30, 560),
(48, 945),
(44, 403),
(36, 228),
(22, 597),
(41, 473),
(3, 758),
(5, 461),
(6, 718),
(26, 276),
(24, 611),
(21, 118),
(22, 537),
(54, 813),
(55, 388),
(16, 959),
(42, 385),
(51, 400),
(18, 791),
(16, 743),
(21, 765),
(53, 155),
(32, 864),
(37, 743),
(20, 391),
(49, 614),
(7, 775),
(34, 95),
(4, 896),
(16, 542),
(39, 129),
(11, 898),
(20, 705),
(5, 483),
(18, 734),
(43, 337),
(30, 653),
(7, 433),
(56, 633),
(49, 657),
(11, 634),
(39, 18),
(40, 495),
(19, 682),
(6, 448),
(39, 248),
(4, 257),
(3, 834),
(25, 565),
(26, 115),
(52, 35),
(31, 41),
(2, 742),
(12, 961),
(43, 940),
(15, 998),
(37, 884),
(26, 513),
(33, 761),
(37, 728),
(5, 664),
(46, 761),
(47, 785),
(15, 200),
(40, 597),
(32, 327),
(28, 285),
(32, 486),
(16, 692),
(50, 870),
(32, 419),
(53, 668),
(38, 59),
(48, 954),
(24, 161),
(45, 480),
(53, 440),
(43, 331),
(17, 529),
(46, 168),
(13, 588),
(38, 809),
(49, 993),
(5, 382),
(33, 464),
(30, 11),
(27, 586),
(37, 813),
(49, 434),
(15, 633),
(29, 192),
(18, 554),
(52, 783),
(16, 673),
(47, 415),
(2, 329),
(29, 906),
(37, 442),
(37, 279),
(43, 540),
(46, 155),
(34, 984),
(11, 436),
(40, 793),
(22, 945),
(49, 2),
(39, 516),
(27, 36),
(51, 44),
(1, 325),
(2, 575),
(32, 605),
(52, 942),
(4, 929),
(10, 365),
(27, 316),
(46, 875),
(52, 453),
(9, 33),
(26, 50),
(19, 463),
(37, 516),
(4, 329),
(32, 574),
(21, 491),
(38, 83),
(13, 373),
(26, 620),
(18, 670),
(3, 454),
(24, 668),
(36, 424),
(31, 550),
(15, 944),
(53, 286),
(49, 580),
(40, 886),
(44, 682),
(15, 278),
(2, 368),
(44, 792),
(19, 482),
(41, 772),
(55, 272),
(19, 59),
(50, 162),
(36, 349),
(23, 527),
(21, 689),
(21, 579),
(43, 757),
(6, 872),
(34, 21),
(31, 446),
(9, 242),
(37, 918),
(54, 152),
(23, 816),
(40, 213),
(1, 494),
(27, 988),
(2, 486),
(33, 823),
(1, 912),
(17, 409),
(4, 18),
(45, 273),
(54, 830),
(28, 766),
(51, 988),
(42, 898),
(54, 749),
(35, 916),
(51, 576),
(32, 591),
(4, 288),
(51, 419),
(39, 566),
(20, 215),
(50, 805),
(15, 475),
(31, 418),
(38, 674),
(45, 104),
(50, 812),
(20, 341),
(30, 751),
(3, 79),
(29, 526),
(9, 181),
(14, 264),
(9, 312),
(49, 433),
(48, 847),
(28, 887),
(16, 684),
(2, 356),
(43, 543),
(32, 949),
(9, 21),
(6, 838),
(8, 760),
(54, 488),
(28, 677),
(47, 673),
(9, 564),
(19, 833),
(18, 760),
(19, 533),
(17, 303),
(16, 171),
(24, 162),
(49, 814),
(51, 977),
(6, 795),
(1, 424),
(37, 340),
(9, 105),
(24, 571),
(50, 658),
(7, 331),
(54, 701),
(53, 396),
(6, 154),
(7, 317),
(39, 138),
(48, 983),
(18, 233),
(13, 517),
(28, 371),
(52, 344),
(33, 612),
(56, 113),
(38, 731),
(38, 760),
(54, 719),
(53, 513),
(51, 948),
(49, 273),
(43, 915),
(6, 396),
(9, 525),
(34, 536),
(34, 131),
(32, 374),
(6, 820),
(11, 436),
(22, 96),
(45, 590),
(50, 834),
(8, 700),
(23, 514),
(47, 602),
(28, 858),
(33, 50),
(20, 551),
(30, 590),
(46, 908),
(4, 401),
(6, 359),
(16, 147),
(25, 658),
(53, 418),
(51, 346),
(36, 829),
(34, 887),
(14, 121),
(9, 450),
(27, 327),
(14, 667),
(17, 196),
(25, 245),
(35, 257),
(17, 370),
(36, 676),
(51, 164),
(8, 135),
(42, 939),
(2, 893),
(6, 604),
(25, 66),
(50, 299),
(24, 775),
(11, 458),
(30, 425),
(43, 454),
(49, 268),
(41, 612),
(46, 862),
(18, 322),
(7, 493),
(34, 374),
(48, 879),
(43, 132),
(46, 336),
(53, 284),
(44, 234),
(49, 207),
(38, 384),
(14, 242),
(16, 785),
(2, 532),
(42, 679),
(4, 415),
(35, 20),
(24, 732),
(39, 104),
(40, 479),
(39, 656),
(24, 925),
(16, 637),
(14, 539),
(13, 324),
(31, 779),
(10, 491),
(28, 167),
(17, 232),
(45, 601),
(50, 92),
(19, 551),
(45, 385),
(36, 316),
(53, 463),
(30, 988),
(18, 90),
(31, 897),
(20, 162),
(30, 938),
(43, 69),
(54, 518),
(50, 930),
(40, 361),
(48, 92),
(35, 564),
(55, 523),
(17, 684),
(33, 307),
(23, 422),
(20, 910),
(25, 378),
(26, 704),
(3, 185),
(6, 426),
(27, 576),
(20, 761),
(44, 172),
(26, 363),
(33, 285),
(30, 679),
(19, 337),
(48, 984),
(2, 970),
(10, 920),
(27, 30),
(9, 363),
(54, 300),
(2, 541),
(48, 414),
(44, 284),
(21, 162),
(55, 215),
(46, 759),
(23, 736),
(4, 798),
(8, 98),
(42, 206),
(8, 610),
(4, 993),
(25, 188),
(44, 871),
(31, 918),
(25, 299),
(17, 797),
(5, 390),
(41, 98),
(18, 37),
(6, 178),
(8, 577),
(2, 593),
(30, 97),
(40, 462),
(49, 600),
(24, 49),
(39, 652),
(42, 728),
(2, 33),
(11, 155),
(9, 648),
(38, 33),
(17, 181),
(30, 935),
(24, 492),
(11, 514),
(29, 823),
(11, 873),
(19, 676),
(18, 187),
(35, 682),
(21, 281),
(16, 701),
(29, 682),
(9, 950),
(8, 988),
(33, 358),
(3, 981),
(56, 17),
(41, 149),
(42, 209),
(56, 413),
(6, 986),
(43, 883),
(25, 560),
(38, 37),
(33, 712),
(38, 212),
(12, 80),
(7, 532),
(9, 207),
(15, 815),
(25, 20),
(47, 76),
(9, 140),
(8, 875),
(44, 65),
(14, 58),
(18, 601),
(47, 60),
(49, 277),
(48, 296),
(41, 790),
(19, 264),
(7, 150),
(34, 208),
(10, 459),
(38, 161),
(56, 4),
(45, 108),
(46, 81),
(12, 161),
(43, 208),
(11, 649),
(53, 191),
(42, 228),
(45, 550),
(44, 824),
(5, 506),
(2, 225),
(20, 400),
(24, 710),
(26, 587),
(6, 824),
(49, 617),
(18, 35),
(24, 888),
(25, 426),
(42, 107),
(19, 608),
(49, 411),
(8, 429),
(12, 639),
(22, 9),
(15, 146),
(22, 506),
(8, 171),
(43, 651),
(19, 958),
(55, 582),
(14, 646),
(40, 2),
(28, 107),
(56, 538),
(41, 530),
(36, 73),
(44, 12),
(49, 147),
(33, 366),
(19, 520),
(53, 880),
(30, 741),
(11, 348),
(8, 853),
(19, 560),
(40, 869),
(41, 560),
(17, 625),
(42, 611),
(54, 639),
(53, 573),
(27, 560),
(24, 997),
(8, 19),
(46, 71),
(1, 577),
(17, 666),
(5, 730),
(33, 51),
(46, 487),
(55, 505),
(34, 730),
(7, 317),
(24, 964),
(46, 685),
(5, 302),
(18, 119),
(15, 804),
(22, 915),
(28, 244),
(36, 70),
(20, 972),
(26, 592),
(8, 424),
(29, 378),
(34, 819),
(19, 997),
(40, 994),
(30, 873),
(31, 584),
(37, 647),
(43, 439),
(21, 3),
(2, 95),
(42, 806),
(29, 342),
(17, 790),
(48, 230),
(27, 327),
(24, 367),
(37, 130),
(20, 247),
(22, 875),
(28, 202),
(21, 680),
(16, 916),
(17, 492),
(25, 508),
(20, 84),
(5, 347),
(8, 227),
(22, 589),
(26, 913),
(37, 518),
(25, 204),
(36, 298),
(14, 823),
(9, 579),
(14, 917),
(40, 700),
(27, 719),
(28, 893),
(29, 39),
(32, 456),
(20, 66),
(13, 811),
(27, 259),
(45, 214),
(5, 785),
(43, 663),
(56, 625),
(21, 859),
(43, 694),
(48, 365),
(44, 558),
(21, 813),
(22, 720),
(41, 864),
(25, 711),
(6, 279),
(3, 984),
(43, 149),
(54, 71),
(36, 484),
(11, 234),
(55, 864),
(32, 792),
(21, 731),
(32, 663),
(49, 819),
(31, 183),
(40, 985),
(5, 783),
(16, 493),
(42, 994),
(50, 580),
(54, 864),
(31, 820),
(49, 418),
(34, 106),
(49, 251),
(3, 98),
(22, 572),
(20, 197),
(54, 898),
(12, 945),
(14, 561),
(44, 162),
(35, 988),
(23, 669),
(10, 202),
(42, 842),
(26, 524),
(22, 201),
(47, 759),
(18, 901),
(8, 202),
(1, 498),
(39, 768),
(28, 205),
(15, 922),
(47, 117),
(37, 926),
(42, 949),
(19, 985),
(13, 452),
(34, 297),
(4, 869),
(15, 430),
(24, 423),
(2, 622),
(47, 107),
(14, 31),
(48, 716),
(17, 391),
(53, 414),
(36, 539),
(50, 529),
(14, 451),
(30, 306),
(30, 464),
(35, 945),
(21, 152),
(6, 501),
(5, 144),
(48, 524),
(38, 437),
(50, 932),
(18, 70),
(2, 196),
(13, 603),
(24, 519),
(11, 142),
(25, 127),
(15, 131),
(43, 778),
(32, 170),
(39, 773),
(32, 621),
(6, 747),
(21, 978),
(19, 655),
(32, 681),
(39, 420),
(1, 602),
(9, 853),
(38, 590),
(45, 11),
(6, 382),
(46, 919),
(22, 987),
(47, 735),
(1, 427),
(51, 534),
(16, 515),
(13, 47),
(16, 877),
(47, 359),
(36, 717),
(47, 390),
(4, 245),
(53, 870),
(50, 391),
(5, 633),
(45, 197),
(37, 801),
(47, 249),
(13, 922),
(24, 875),
(17, 42),
(13, 517),
(44, 175),
(37, 877),
(43, 158),
(55, 890),
(4, 924),
(56, 551),
(24, 228),
(26, 918),
(13, 931),
(24, 443),
(44, 794),
(53, 191),
(33, 211),
(49, 920),
(35, 137),
(22, 580),
(31, 37),
(6, 520),
(35, 795),
(32, 527),
(53, 194),
(33, 623),
(19, 87),
(41, 494),
(37, 69),
(33, 549),
(28, 573),
(29, 28),
(18, 978),
(19, 787),
(17, 157),
(49, 323),
(14, 490),
(56, 4),
(19, 205),
(23, 897),
(28, 179),
(36, 202),
(15, 327),
(54, 290),
(47, 971),
(5, 180),
(5, 988),
(22, 653),
(22, 96),
(48, 912),
(26, 757),
(28, 947),
(10, 53),
(16, 94),
(46, 189),
(30, 659),
(25, 893),
(29, 362),
(56, 695),
(49, 230),
(33, 448),
(30, 260),
(40, 744),
(10, 251),
(31, 801),
(22, 234),
(48, 507),
(46, 66),
(5, 960),
(3, 99),
(21, 884),
(22, 953),
(19, 686),
(1, 420),
(15, 946),
(15, 216),
(13, 830),
(11, 371),
(18, 293),
(50, 713),
(46, 723),
(1, 624),
(1, 433),
(20, 295),
(56, 206),
(52, 332),
(49, 309),
(17, 423),
(16, 143),
(33, 578),
(24, 475),
(22, 338),
(35, 415),
(35, 304),
(46, 334),
(55, 963),
(45, 461),
(20, 14),
(35, 373),
(49, 550),
(37, 8),
(11, 319),
(43, 962),
(23, 21),
(13, 386),
(24, 644),
(22, 455),
(50, 159),
(46, 937),
(35, 314),
(45, 86),
(45, 295),
(31, 228),
(19, 254),
(56, 640),
(16, 65),
(52, 419),
(31, 788),
(13, 772),
(34, 242),
(43, 41),
(18, 820),
(16, 446),
(53, 528),
(14, 38),
(41, 257),
(5, 998),
(45, 478),
(43, 750),
(12, 133),
(5, 791),
(48, 520),
(13, 779),
(32, 149),
(2, 109),
(23, 222),
(48, 988),
(43, 830),
(14, 48),
(3, 782),
(4, 665),
(21, 35),
(14, 478),
(17, 740),
(21, 984),
(12, 281),
(11, 153),
(31, 578),
(34, 891),
(42, 650),
(38, 280),
(53, 501),
(46, 204),
(30, 582),
(16, 986),
(13, 833),
(17, 597),
(41, 292),
(14, 463),
(33, 848),
(9, 461),
(48, 555),
(39, 229),
(49, 797),
(12, 63),
(41, 271),
(45, 436),
(11, 553),
(41, 313),
(51, 247),
(31, 164),
(42, 503),
(17, 36),
(52, 974),
(24, 111),
(11, 682),
(34, 557),
(9, 745),
(31, 482),
(6, 21),
(44, 713),
(38, 370),
(20, 22),
(23, 209),
(13, 293),
(23, 980),
(50, 192),
(13, 131),
(48, 327),
(41, 576),
(3, 874),
(34, 690),
(33, 872),
(32, 291),
(26, 588),
(46, 693),
(4, 369),
(52, 142),
(8, 153),
(31, 731),
(35, 222),
(47, 866),
(10, 395),
(37, 235),
(29, 645),
(19, 360),
(16, 10),
(8, 914),
(23, 910),
(18, 327),
(41, 89),
(22, 342),
(37, 576),
(38, 832),
(31, 414),
(14, 726),
(14, 855),
(8, 134),
(2, 396),
(35, 188),
(52, 918),
(34, 354),
(12, 551),
(51, 85),
(17, 415),
(27, 769),
(56, 975),
(10, 928),
(13, 709),
(18, 191),
(4, 10),
(43, 451),
(49, 426),
(34, 230),
(2, 996),
(43, 898),
(36, 112),
(21, 541),
(38, 986),
(1, 145),
(32, 106),
(51, 200),
(17, 262),
(37, 29),
(12, 641),
(4, 142),
(8, 907),
(50, 593),
(38, 476),
(19, 344),
(1, 347),
(46, 120),
(2, 651),
(55, 697),
(5, 345),
(32, 151),
(43, 929),
(22, 593),
(25, 765),
(38, 993),
(18, 680),
(42, 370),
(21, 414),
(5, 536),
(42, 947),
(46, 509),
(43, 205),
(5, 284),
(30, 817),
(4, 959),
(32, 844),
(4, 657),
(52, 589),
(53, 797),
(37, 689),
(9, 213),
(31, 710),
(33, 28),
(43, 440),
(25, 817),
(15, 506),
(34, 61),
(40, 171),
(24, 127),
(51, 286),
(42, 185),
(25, 664),
(54, 649),
(44, 132),
(3, 758),
(20, 419),
(18, 955),
(22, 70),
(18, 759),
(36, 673),
(36, 657),
(13, 474),
(43, 275),
(23, 912),
(33, 844),
(13, 923),
(31, 940),
(50, 154),
(16, 236),
(8, 885),
(55, 135),
(50, 150),
(3, 862),
(44, 320),
(44, 625),
(50, 151),
(46, 877),
(33, 311),
(29, 372),
(15, 491),
(40, 914),
(19, 906),
(41, 47),
(26, 882),
(33, 398),
(20, 814),
(36, 491),
(26, 99),
(42, 730),
(7, 797),
(31, 594),
(53, 428),
(2, 706),
(31, 327),
(40, 950),
(45, 251),
(24, 71),
(43, 749),
(29, 781),
(31, 681),
(7, 843),
(39, 12),
(49, 795),
(38, 606),
(31, 797),
(4, 339),
(32, 958),
(48, 157),
(33, 469),
(41, 104),
(19, 769),
(27, 652),
(32, 136),
(28, 789),
(47, 78),
(10, 470),
(12, 217),
(53, 915),
(55, 785),
(11, 832),
(50, 405),
(37, 859),
(37, 53),
(13, 780),
(29, 51),
(7, 9),
(32, 709),
(30, 567),
(9, 948),
(33, 183),
(56, 204),
(12, 242),
(11, 6),
(22, 844),
(17, 519),
(27, 962),
(35, 545),
(29, 764),
(16, 955),
(55, 626),
(53, 123),
(12, 882),
(34, 639),
(40, 58),
(11, 259),
(4, 462),
(51, 640),
(54, 249),
(22, 590),
(18, 319),
(10, 159),
(14, 543),
(44, 520),
(50, 426),
(41, 861),
(19, 422),
(22, 59),
(10, 680),
(47, 635),
(14, 949),
(53, 25),
(20, 399),
(28, 463),
(20, 100),
(18, 781),
(1, 524),
(55, 729),
(41, 550),
(51, 801),
(52, 23),
(15, 15),
(18, 943),
(49, 686),
(44, 246),
(11, 763),
(48, 202),
(51, 421),
(7, 649),
(54, 735),
(50, 390),
(35, 951),
(36, 631),
(29, 396),
(27, 886),
(1, 718),
(22, 349),
(3, 940),
(1, 378),
(6, 750),
(19, 569),
(18, 633),
(45, 541),
(28, 895),
(51, 702),
(36, 174),
(45, 133),
(36, 643),
(10, 847),
(25, 971),
(41, 416),
(23, 365),
(49, 32),
(46, 273),
(8, 163),
(5, 511),
(24, 998),
(54, 896),
(9, 320),
(3, 105),
(20, 607),
(14, 616),
(37, 806),
(42, 430),
(51, 629),
(5, 292),
(52, 627),
(9, 400),
(42, 127),
(48, 40),
(1, 417),
(6, 290),
(11, 814),
(16, 889),
(37, 915),
(25, 548),
(1, 720),
(5, 47),
(44, 90),
(34, 238),
(10, 151),
(8, 776),
(28, 295),
(14, 889),
(35, 212),
(40, 678),
(4, 129),
(31, 829),
(26, 522),
(30, 787),
(37, 566),
(56, 773),
(9, 266),
(43, 52),
(40, 90),
(54, 64),
(6, 508),
(23, 379),
(30, 378),
(14, 846),
(35, 208),
(55, 682),
(28, 938),
(1, 213),
(30, 494),
(9, 155),
(5, 282),
(8, 504),
(22, 765),
(33, 391),
(30, 459),
(29, 896),
(35, 766),
(27, 326),
(37, 900),
(46, 919),
(18, 258),
(52, 991),
(41, 300),
(54, 891),
(35, 959),
(22, 354),
(46, 508),
(31, 728),
(47, 881),
(10, 876),
(6, 226),
(52, 452),
(54, 563),
(13, 440),
(51, 185),
(13, 914),
(31, 176),
(47, 800),
(31, 244),
(43, 302),
(53, 832),
(24, 241),
(39, 906),
(24, 521),
(26, 65),
(16, 765),
(38, 185),
(6, 877),
(18, 209),
(42, 150),
(27, 248),
(45, 75),
(20, 629),
(43, 65),
(39, 992),
(10, 430),
(54, 295),
(46, 138),
(48, 645),
(44, 123),
(45, 211),
(14, 738),
(6, 595),
(28, 598),
(51, 219),
(45, 227),
(6, 319),
(17, 776),
(51, 382),
(28, 869),
(48, 416),
(50, 27),
(20, 544),
(29, 563),
(15, 291),
(42, 457),
(40, 86),
(35, 329),
(49, 282),
(29, 952),
(12, 604),
(31, 935),
(52, 421),
(41, 857),
(27, 171),
(13, 963),
(20, 967),
(11, 9),
(56, 678),
(40, 73),
(8, 410),
(25, 329),
(34, 680),
(37, 382),
(1, 821),
(40, 153),
(53, 853),
(16, 950),
(13, 623),
(33, 325),
(49, 114),
(46, 77),
(32, 9),
(11, 145),
(56, 132),
(27, 74),
(12, 190),
(43, 42),
(18, 698),
(37, 43),
(2, 198),
(52, 297),
(20, 693),
(3, 487),
(35, 994),
(45, 232),
(42, 811),
(38, 112),
(26, 940),
(18, 712),
(54, 146),
(49, 995),
(12, 137),
(55, 201),
(11, 956),
(42, 945),
(48, 133),
(31, 336),
(2, 37),
(11, 729),
(2, 681),
(54, 348),
(30, 364),
(9, 264),
(8, 820),
(50, 30),
(21, 526),
(42, 688),
(13, 17),
(28, 862),
(35, 916),
(42, 492),
(14, 355),
(19, 684),
(56, 627),
(39, 815),
(12, 720),
(24, 846),
(42, 628),
(5, 936),
(9, 917),
(56, 976),
(32, 109),
(2, 463),
(48, 985),
(18, 206),
(17, 952),
(7, 282),
(18, 860),
(42, 823),
(29, 372),
(13, 414),
(48, 24),
(42, 814),
(54, 164),
(51, 277),
(17, 625),
(47, 284),
(56, 974),
(48, 60),
(27, 428),
(8, 435),
(35, 758),
(6, 868),
(17, 967),
(53, 844),
(27, 899),
(11, 442),
(50, 137),
(3, 529),
(46, 598),
(42, 671),
(12, 136),
(20, 149),
(16, 476),
(3, 783),
(22, 727),
(22, 758),
(18, 991),
(44, 870),
(8, 373),
(47, 141),
(5, 285),
(29, 42),
(1, 724),
(52, 603),
(23, 492),
(22, 930),
(48, 803),
(31, 976),
(5, 467),
(24, 640),
(16, 306),
(4, 747),
(19, 199),
(8, 727),
(53, 420),
(42, 415),
(12, 207),
(37, 523),
(40, 217),
(41, 57),
(2, 579),
(32, 970),
(44, 27),
(3, 497),
(1, 95),
(46, 237),
(27, 883),
(43, 791),
(52, 498),
(42, 342),
(54, 760),
(14, 662),
(23, 108),
(50, 999),
(15, 606),
(19, 474),
(4, 656),
(39, 688),
(3, 212),
(19, 371),
(51, 135),
(16, 897),
(47, 747),
(32, 925),
(23, 827),
(40, 15),
(38, 971),
(52, 450),
(34, 299),
(55, 278),
(51, 355),
(38, 512),
(51, 958),
(14, 245),
(32, 289),
(2, 7),
(29, 62),
(42, 377),
(49, 467),
(43, 435),
(19, 123),
(21, 572),
(47, 653),
(10, 213),
(5, 394),
(31, 980),
(23, 836),
(45, 577),
(8, 127),
(21, 733),
(56, 941),
(17, 223),
(2, 198),
(28, 144),
(43, 337),
(44, 249),
(19, 392),
(50, 588),
(48, 441),
(3, 4),
(9, 548),
(39, 800),
(27, 152),
(36, 514),
(16, 936),
(54, 277),
(40, 900),
(2, 820),
(46, 50),
(12, 365),
(17, 782),
(9, 888),
(47, 14),
(14, 833),
(23, 437),
(7, 273),
(16, 258),
(2, 207),
(39, 812),
(10, 177),
(43, 816),
(45, 481),
(28, 660),
(47, 727),
(37, 388),
(21, 624),
(17, 462),
(17, 172),
(41, 928),
(50, 108),
(6, 405),
(40, 276),
(42, 373),
(12, 19),
(52, 68),
(37, 481),
(13, 482),
(5, 986),
(6, 833),
(28, 132),
(41, 808),
(45, 876),
(28, 103),
(29, 650),
(25, 376),
(44, 179),
(39, 671),
(31, 974),
(1, 393),
(34, 340),
(44, 810),
(33, 396),
(30, 710),
(11, 507),
(38, 798),
(42, 736),
(4, 604),
(38, 709),
(20, 327),
(16, 614),
(3, 109),
(13, 367),
(2, 961),
(19, 327),
(3, 234),
(17, 733),
(44, 823),
(11, 110),
(20, 277),
(16, 88),
(1, 578),
(47, 638),
(6, 832),
(28, 418),
(9, 964),
(30, 435),
(14, 930),
(30, 299),
(7, 163),
(1, 776),
(42, 482),
(22, 534),
(49, 382),
(9, 829),
(7, 88),
(48, 934),
(21, 411),
(31, 964),
(5, 887),
(6, 468),
(56, 299),
(54, 492),
(56, 866),
(17, 270),
(14, 23),
(34, 984),
(4, 598),
(29, 690),
(1, 938),
(47, 520),
(51, 949),
(36, 279),
(20, 115),
(21, 516),
(46, 688),
(5, 922),
(56, 168),
(47, 59),
(12, 819),
(18, 68),
(27, 896),
(4, 43),
(34, 99),
(11, 76),
(2, 709),
(26, 46),
(19, 634),
(7, 620),
(19, 204),
(35, 950),
(28, 399),
(47, 500),
(22, 164),
(22, 415),
(21, 829),
(11, 796),
(29, 754),
(35, 176),
(31, 310),
(28, 537),
(8, 58),
(3, 869),
(10, 990),
(50, 474),
(14, 200),
(37, 929),
(15, 691),
(46, 841),
(22, 490),
(4, 799),
(26, 673),
(2, 428),
(54, 663),
(40, 293),
(51, 874),
(31, 20),
(10, 763),
(6, 566),
(14, 318),
(26, 519),
(49, 443),
(32, 349),
(32, 883),
(7, 510),
(26, 363),
(45, 585),
(29, 385),
(25, 432),
(22, 640),
(15, 218),
(56, 416),
(44, 321),
(55, 567),
(5, 985),
(43, 172),
(2, 980),
(22, 429),
(46, 977),
(17, 301),
(36, 516),
(8, 60),
(48, 318),
(46, 823),
(35, 10),
(43, 135),
(26, 863),
(35, 970),
(20, 213),
(19, 287),
(56, 276),
(18, 418),
(35, 228),
(41, 64),
(10, 59),
(6, 258),
(17, 954),
(56, 4),
(45, 53),
(44, 536),
(25, 544),
(30, 648),
(17, 295),
(7, 973),
(19, 760),
(6, 860),
(5, 964),
(44, 233),
(40, 788),
(20, 604),
(41, 69),
(1, 688),
(44, 90),
(44, 878),
(5, 817),
(11, 372),
(39, 91),
(9, 644),
(25, 278),
(13, 983),
(20, 209),
(45, 847),
(47, 908),
(16, 589),
(48, 83),
(12, 164),
(22, 229),
(46, 764),
(19, 454),
(1, 164),
(2, 726),
(31, 98),
(7, 930),
(19, 697),
(52, 190),
(6, 248),
(23, 672),
(53, 642),
(50, 347),
(38, 728),
(19, 925),
(20, 602),
(9, 45),
(9, 662),
(13, 822),
(11, 652),
(9, 246),
(6, 468),
(13, 280),
(14, 915),
(22, 570),
(42, 875),
(27, 236),
(32, 106),
(3, 182),
(1, 974),
(25, 546),
(29, 243),
(5, 313),
(11, 814),
(53, 732),
(39, 587),
(7, 189),
(42, 547),
(56, 130),
(17, 426),
(24, 73),
(22, 229),
(35, 371),
(12, 808),
(26, 573),
(56, 814),
(38, 16),
(31, 977),
(52, 877),
(21, 934),
(29, 481),
(34, 795),
(52, 619),
(12, 517),
(15, 933),
(9, 800),
(25, 3),
(51, 24),
(36, 759),
(44, 528),
(51, 105);




/*przelewy*/
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (312, 261, 4733.28, '2021-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (195, 184, 9202.48, '2022-01-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 46, 5026.32, '2022-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 757, 2618.27, '2021-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (915, 345, 7033.46, '2022-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (283, 113, 218.64, '2023-04-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (34, 384, 7464.16, '2023-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (220, 990, 4599.53, '2021-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (812, 421, 6277.08, '2020-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (48, 309, 3028.93, '2021-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (938, 9, 1705.04, '2024-07-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (48, 441, 8827.33, '2022-07-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (572, 897, 6693.01, '2022-05-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (682, 205, 7580.08, '2020-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (10, 965, 424.39, '2020-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (960, 913, 8503.52, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (436, 181, 7698.51, '2024-04-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (704, 487, 3846.4, '2021-07-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (918, 118, 9056.63, '2022-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (752, 289, 3407.33, '2022-10-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (799, 774, 1610.77, '2023-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (927, 95, 118.2, '2022-02-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (548, 351, 8279.72, '2021-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (522, 648, 1291.32, '2022-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (797, 374, 8192.17, '2020-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (911, 120, 9977.26, '2021-02-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (437, 77, 4711.99, '2021-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (161, 972, 6073.37, '2025-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (122, 619, 5898.44, '2023-03-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (222, 909, 6456.92, '2023-06-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (397, 955, 8440.87, '2020-08-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (508, 933, 1992.01, '2020-04-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (943, 404, 8484.44, '2023-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (966, 554, 5407.37, '2025-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (208, 476, 3642.86, '2025-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (575, 925, 1320.63, '2021-09-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (67, 472, 2536.36, '2025-02-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (45, 621, 225.69, '2021-03-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (826, 863, 1948.83, '2021-03-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (558, 870, 7292.57, '2024-10-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (914, 698, 9779.08, '2022-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (930, 580, 3797.33, '2020-07-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (547, 985, 2940.46, '2020-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (249, 232, 4055.93, '2024-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (59, 858, 365.4, '2021-06-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (58, 20, 152.75, '2023-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (552, 122, 7841.74, '2024-05-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (441, 367, 2406.11, '2021-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (959, 562, 289.83, '2021-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (459, 167, 6021.16, '2023-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (347, 148, 6074.5, '2023-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (10, 437, 4292.79, '2025-01-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (961, 338, 6681.53, '2023-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (39, 390, 570.84, '2023-08-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (981, 272, 8123.31, '2023-04-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (693, 668, 3483.19, '2022-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (747, 482, 8454.33, '2023-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (168, 540, 9507.5, '2020-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (776, 651, 2559.16, '2021-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (93, 867, 3295.31, '2022-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (168, 277, 21.25, '2024-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (792, 865, 6142.78, '2020-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (776, 865, 6623.08, '2021-11-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (339, 52, 60.52, '2025-02-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (363, 85, 6504.4, '2021-12-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (754, 232, 3836.01, '2023-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (737, 521, 5779.74, '2020-08-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (161, 591, 9419.16, '2024-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (773, 54, 5099.27, '2023-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (933, 444, 3434.95, '2023-01-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (912, 684, 7830.02, '2021-02-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (54, 164, 5018.86, '2022-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (109, 828, 1566.77, '2022-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (221, 120, 918.96, '2022-11-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (835, 193, 3452.26, '2024-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (924, 408, 5964.11, '2023-02-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (773, 368, 5627.4, '2024-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (293, 469, 9134.73, '2021-07-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (153, 628, 2317.5, '2020-11-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (139, 87, 4836.49, '2021-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (259, 987, 4881.96, '2024-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (346, 299, 7572.18, '2021-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (119, 117, 7062.98, '2023-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (580, 885, 3629.27, '2024-05-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (397, 406, 8743.63, '2024-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (349, 117, 1098.04, '2021-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (222, 372, 3176.68, '2022-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (752, 895, 479.32, '2021-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (785, 194, 7757.31, '2020-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (616, 745, 808.14, '2024-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (508, 168, 2203.24, '2022-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (691, 574, 734.21, '2022-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (417, 431, 303.68, '2022-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 472, 5787.47, '2024-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (923, 598, 7977.61, '2021-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (209, 577, 6761.53, '2020-07-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (341, 734, 81.97, '2020-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (289, 51, 8665.81, '2020-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (917, 625, 5939.19, '2024-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (693, 361, 5107.77, '2024-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (308, 480, 2888.04, '2021-07-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (42, 90, 3790.88, '2021-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (262, 792, 330.29, '2022-09-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (794, 872, 9523.71, '2024-07-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (438, 874, 4866.72, '2021-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (675, 970, 6267.6, '2024-04-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 638, 9389.3, '2021-08-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (845, 297, 6787.22, '2024-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (319, 424, 2320.17, '2022-05-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (909, 618, 6027.03, '2023-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (300, 941, 1088.68, '2021-05-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (960, 753, 2838.73, '2020-07-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (130, 23, 9814.01, '2024-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (467, 890, 6586.94, '2021-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (55, 536, 3509.92, '2023-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (397, 119, 4060.1, '2021-07-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (411, 332, 8662.98, '2024-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (196, 332, 8071.75, '2023-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (676, 9, 408.47, '2025-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (495, 331, 4482.51, '2022-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (733, 368, 9737.89, '2025-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (552, 295, 6681.55, '2020-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (567, 167, 6551.44, '2023-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (253, 989, 9536.35, '2022-02-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (22, 358, 6911.51, '2023-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (980, 532, 9930.73, '2024-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (261, 312, 9424.02, '2023-10-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (611, 60, 4463.74, '2024-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (146, 159, 9368.25, '2023-06-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (530, 685, 4849.33, '2025-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (839, 427, 2251.77, '2021-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (55, 50, 5505.13, '2022-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (749, 506, 1174.53, '2024-01-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (82, 461, 3888.44, '2020-10-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (652, 494, 6983.52, '2022-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (490, 814, 2246.13, '2020-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (763, 423, 8528.73, '2022-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (308, 687, 23.02, '2021-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (419, 395, 9764.88, '2024-03-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (549, 244, 3377.47, '2022-01-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (446, 374, 8232.85, '2021-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (796, 785, 547.52, '2023-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (170, 946, 9061.9, '2023-11-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (133, 789, 4508.72, '2020-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (201, 289, 1049.03, '2023-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (385, 98, 5161.23, '2020-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (253, 955, 3513.53, '2022-07-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (855, 366, 3356.44, '2024-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (190, 506, 5473.24, '2024-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (374, 646, 1148.28, '2024-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (540, 758, 2486.49, '2022-03-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 126, 6502.16, '2021-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (776, 568, 9527.3, '2020-11-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (896, 223, 7374.16, '2020-11-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (430, 435, 219.48, '2020-05-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (905, 518, 4514.01, '2022-03-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (695, 786, 5140.05, '2022-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (101, 639, 9505.64, '2021-03-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (201, 545, 135.35, '2024-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (866, 554, 5637.96, '2023-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (387, 826, 6238.81, '2025-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (276, 292, 4857.62, '2022-01-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (517, 470, 9787.91, '2021-12-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (711, 145, 3399.79, '2023-01-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (393, 851, 7521.68, '2020-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (450, 799, 1005.52, '2024-08-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (99, 814, 4884.0, '2023-12-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (634, 16, 4519.83, '2021-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (743, 532, 5783.56, '2024-10-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (535, 890, 9373.89, '2021-04-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (173, 336, 3640.85, '2025-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (774, 85, 4901.2, '2024-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (474, 56, 4257.91, '2022-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (501, 924, 538.37, '2020-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 888, 5118.43, '2023-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (723, 498, 2912.52, '2023-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (740, 605, 7304.45, '2021-07-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (168, 861, 4821.78, '2022-09-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (166, 986, 974.92, '2023-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (626, 909, 3639.86, '2020-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (293, 694, 6678.46, '2021-10-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (465, 475, 2838.19, '2023-02-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (567, 351, 5156.4, '2022-03-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (252, 822, 2321.63, '2024-11-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (77, 948, 1504.63, '2023-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (181, 706, 9974.88, '2023-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (350, 485, 6431.59, '2022-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (499, 125, 566.62, '2024-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (884, 857, 2562.1, '2025-01-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (764, 645, 8068.97, '2023-07-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (191, 247, 4250.85, '2021-11-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (285, 88, 4040.95, '2025-01-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (841, 487, 1945.6, '2024-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (890, 464, 4025.18, '2022-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (721, 733, 229.9, '2021-07-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (424, 979, 3323.89, '2023-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (489, 42, 9505.72, '2024-03-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (337, 434, 6400.25, '2020-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (947, 915, 223.69, '2020-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (674, 528, 3693.41, '2022-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (908, 999, 5716.52, '2023-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (346, 22, 6512.14, '2021-07-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (535, 905, 1399.46, '2021-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (875, 952, 8072.38, '2021-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (274, 205, 6042.68, '2021-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (106, 182, 9721.89, '2025-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (486, 137, 9324.19, '2023-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (103, 483, 8128.67, '2024-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (989, 267, 6410.57, '2024-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (504, 824, 7460.64, '2020-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (691, 753, 4893.84, '2023-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 596, 8592.2, '2020-09-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (553, 471, 4473.54, '2021-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (800, 426, 6176.65, '2021-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (356, 605, 1587.58, '2022-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (545, 381, 9742.08, '2023-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (682, 146, 6213.75, '2020-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (963, 35, 4319.85, '2024-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (18, 436, 7182.26, '2022-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (152, 430, 2666.22, '2023-01-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (804, 455, 9824.1, '2021-09-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (558, 382, 8086.16, '2022-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (759, 269, 1757.75, '2024-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (321, 673, 9058.93, '2024-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (309, 575, 3582.09, '2024-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (284, 210, 6049.17, '2023-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (323, 657, 9872.1, '2024-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (830, 866, 2170.92, '2021-10-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (552, 820, 4425.99, '2023-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (326, 573, 4604.58, '2024-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (904, 538, 995.69, '2023-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (963, 399, 1345.6, '2020-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (384, 103, 5631.26, '2024-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (2, 836, 1034.62, '2024-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 131, 9641.64, '2023-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (189, 591, 4787.63, '2025-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (388, 410, 8361.59, '2025-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (818, 64, 7396.51, '2024-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (333, 231, 6776.31, '2023-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (242, 161, 6321.01, '2023-06-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (591, 585, 9069.03, '2022-05-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (211, 875, 831.36, '2023-03-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (38, 789, 6964.78, '2022-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (514, 359, 9440.74, '2025-01-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 732, 54.23, '2021-11-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (775, 447, 1175.81, '2024-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (347, 537, 5817.97, '2022-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (785, 636, 686.37, '2022-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (605, 268, 9515.05, '2021-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (585, 633, 6212.5, '2023-04-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (417, 454, 3576.87, '2024-07-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (646, 879, 5206.48, '2024-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (386, 905, 610.97, '2020-10-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (248, 579, 2501.08, '2024-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (127, 335, 1953.63, '2024-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (345, 830, 1759.33, '2024-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (91, 844, 1796.06, '2023-12-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (218, 419, 4090.61, '2021-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (105, 17, 3724.04, '2021-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (2, 692, 8763.68, '2024-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (735, 378, 8646.77, '2020-10-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (468, 794, 3183.01, '2024-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (622, 187, 4815.6, '2023-10-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (363, 323, 5866.44, '2023-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (966, 466, 3886.67, '2023-08-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (784, 947, 8179.49, '2020-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (674, 757, 27.72, '2024-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (49, 317, 7203.59, '2024-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (979, 81, 58.59, '2021-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (88, 77, 8634.15, '2024-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (774, 402, 8857.27, '2022-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (114, 99, 2668.94, '2022-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (405, 258, 8260.74, '2020-06-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (446, 911, 6110.18, '2022-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (624, 54, 9532.15, '2022-11-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (716, 148, 717.54, '2023-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (654, 192, 9979.94, '2024-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (252, 603, 7217.51, '2024-02-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (482, 626, 5041.83, '2024-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (90, 370, 5667.86, '2022-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (14, 494, 2896.98, '2023-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (191, 606, 6404.11, '2020-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 491, 5573.11, '2020-08-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (323, 529, 2754.03, '2020-12-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (721, 643, 769.82, '2021-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (704, 89, 1830.81, '2020-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (427, 170, 9230.56, '2020-12-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (675, 870, 9168.96, '2024-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (297, 411, 9692.92, '2025-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (517, 261, 1941.31, '2023-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (461, 861, 9502.34, '2023-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (227, 218, 4157.44, '2021-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (403, 867, 9911.07, '2020-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (202, 827, 5141.07, '2023-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (428, 205, 5295.2, '2020-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (791, 356, 7391.11, '2022-05-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (218, 542, 7036.12, '2020-06-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (795, 511, 347.6, '2023-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (680, 544, 2315.78, '2021-07-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (979, 412, 9217.97, '2020-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 501, 8137.54, '2022-04-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (809, 999, 9028.44, '2024-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (206, 821, 1809.13, '2023-07-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (706, 704, 1425.78, '2024-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (198, 698, 5762.53, '2025-01-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (544, 673, 2440.08, '2020-04-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (919, 864, 3608.82, '2021-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (89, 130, 1110.69, '2020-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (516, 543, 1915.29, '2024-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (321, 447, 9053.9, '2022-12-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (501, 674, 741.61, '2024-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (327, 979, 6227.64, '2021-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (71, 108, 5831.83, '2021-08-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (73, 27, 6905.06, '2024-02-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (984, 459, 3615.31, '2020-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (290, 148, 8696.34, '2021-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (970, 888, 3709.67, '2022-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (384, 62, 8343.27, '2023-01-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (533, 904, 3868.35, '2021-04-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (779, 392, 8976.48, '2024-02-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (965, 438, 5508.32, '2023-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (602, 902, 4029.77, '2021-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (8, 673, 5409.47, '2024-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (484, 451, 1765.12, '2023-01-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (759, 891, 1410.01, '2024-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (70, 225, 8735.01, '2020-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (101, 172, 5348.32, '2025-03-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (138, 706, 4051.49, '2023-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (792, 629, 1178.54, '2023-06-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (603, 340, 1115.42, '2024-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (892, 960, 5901.97, '2024-06-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (586, 195, 5888.32, '2020-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (477, 624, 4805.8, '2023-02-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (807, 625, 9204.34, '2023-05-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (338, 253, 7735.89, '2022-12-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (588, 521, 7817.82, '2022-09-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (492, 442, 4179.69, '2022-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (453, 964, 7027.87, '2023-06-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (120, 908, 3750.82, '2024-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (642, 745, 9363.56, '2023-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (122, 374, 6849.47, '2022-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (759, 824, 4669.42, '2022-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (588, 464, 3819.13, '2020-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (16, 668, 6403.94, '2022-04-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (19, 131, 6431.4, '2021-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (467, 987, 2044.26, '2021-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (206, 493, 2215.52, '2023-08-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (540, 80, 7585.11, '2020-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (616, 239, 6743.42, '2021-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (436, 816, 5593.34, '2022-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (701, 984, 546.84, '2020-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (195, 25, 7709.58, '2024-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (285, 321, 218.72, '2022-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (174, 962, 4156.86, '2023-06-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (4, 977, 4336.68, '2022-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (872, 461, 6868.14, '2020-04-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (21, 277, 7584.17, '2020-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (616, 448, 6825.17, '2020-05-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (79, 470, 5286.01, '2023-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 14, 4138.49, '2023-06-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (251, 531, 946.73, '2021-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 656, 3104.4, '2023-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 119, 1474.19, '2023-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (955, 424, 8506.15, '2024-03-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (432, 265, 353.01, '2021-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (766, 293, 3387.85, '2022-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (764, 173, 6967.26, '2024-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 108, 1182.42, '2024-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (563, 646, 7125.1, '2021-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (834, 931, 2772.29, '2022-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (791, 660, 5580.37, '2020-10-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (433, 97, 3742.01, '2021-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (626, 391, 4322.14, '2020-08-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (338, 985, 2104.16, '2022-06-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (734, 792, 2341.47, '2020-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (77, 192, 7374.64, '2024-12-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (75, 420, 3393.68, '2024-08-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (778, 258, 4858.56, '2021-08-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (503, 113, 1551.83, '2021-03-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (284, 294, 6069.23, '2024-01-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (808, 105, 5733.03, '2024-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (122, 70, 9880.73, '2023-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (971, 282, 6450.28, '2023-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (523, 704, 7900.57, '2020-09-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (671, 848, 6354.88, '2023-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (51, 533, 6670.81, '2020-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (911, 317, 1754.71, '2021-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (406, 497, 3966.7, '2022-11-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 301, 1125.19, '2022-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (383, 288, 4661.38, '2023-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (450, 532, 7326.84, '2024-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (75, 353, 3803.1, '2023-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (74, 289, 9837.72, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (625, 878, 3571.01, '2023-11-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (714, 913, 7102.58, '2021-01-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (705, 697, 9081.55, '2021-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (36, 854, 7261.93, '2021-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (977, 982, 9345.49, '2023-06-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (763, 180, 9772.62, '2022-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (471, 321, 7230.94, '2024-10-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (964, 531, 1782.19, '2023-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (279, 519, 5990.0, '2023-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (800, 260, 3552.43, '2020-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (930, 441, 6631.26, '2023-05-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (41, 30, 2297.74, '2020-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (672, 914, 286.21, '2021-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (515, 24, 798.82, '2024-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (193, 157, 4748.72, '2021-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (53, 831, 9682.98, '2020-06-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (743, 161, 5586.5, '2023-11-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (22, 52, 40.81, '2024-03-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (470, 607, 6642.48, '2022-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (661, 157, 1321.01, '2022-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (681, 722, 7796.52, '2022-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (897, 573, 305.28, '2022-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (563, 13, 8969.78, '2023-11-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (124, 663, 4561.27, '2023-08-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (55, 65, 9478.79, '2021-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (580, 874, 457.53, '2021-07-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (747, 192, 4155.34, '2023-08-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (923, 561, 3312.73, '2020-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (169, 989, 6135.33, '2024-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (218, 445, 6285.36, '2022-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (246, 405, 7179.0, '2023-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (590, 859, 2939.14, '2020-11-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (695, 620, 2210.89, '2020-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (882, 641, 8824.91, '2023-10-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (189, 297, 8659.72, '2022-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (792, 602, 8037.32, '2020-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (398, 222, 6595.1, '2023-11-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (9, 846, 9028.87, '2024-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (857, 591, 7042.13, '2023-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (543, 351, 2115.55, '2024-03-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (288, 927, 2734.24, '2021-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 493, 5196.73, '2022-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (197, 828, 1925.38, '2020-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (821, 583, 3413.99, '2023-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (224, 31, 1316.46, '2023-07-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (15, 558, 8510.46, '2020-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (80, 488, 4415.78, '2022-06-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (606, 666, 7882.88, '2022-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (506, 551, 8493.7, '2022-12-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (681, 674, 1724.53, '2020-11-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (91, 862, 5004.23, '2025-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (603, 114, 9733.21, '2023-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (761, 750, 4928.15, '2022-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (324, 105, 5827.02, '2023-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (471, 654, 5926.93, '2020-04-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (706, 960, 4663.88, '2022-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (549, 544, 9676.11, '2023-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (470, 399, 969.81, '2022-06-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (735, 677, 2755.78, '2022-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (372, 476, 653.6, '2022-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (969, 287, 7845.94, '2024-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (702, 262, 8410.46, '2022-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (926, 723, 2141.72, '2020-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (121, 466, 3989.88, '2022-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (695, 989, 3852.31, '2021-09-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (183, 562, 5430.24, '2023-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (562, 475, 2809.52, '2023-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (528, 606, 8930.27, '2024-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (999, 699, 4872.41, '2020-12-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (647, 713, 5582.81, '2024-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (513, 929, 8220.14, '2024-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (729, 281, 4427.57, '2022-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (202, 59, 5572.59, '2022-08-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (913, 513, 9204.41, '2021-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (37, 308, 8417.13, '2021-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 99, 9350.06, '2022-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (311, 858, 7178.39, '2022-03-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (274, 515, 3434.71, '2020-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (579, 504, 2448.02, '2023-12-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (780, 859, 5644.49, '2023-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (72, 260, 3226.01, '2023-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (129, 95, 8197.41, '2021-10-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (841, 813, 7763.22, '2024-05-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (264, 789, 466.37, '2022-11-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 903, 3800.26, '2022-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (216, 283, 4496.54, '2020-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (611, 272, 3054.31, '2021-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (413, 914, 2253.4, '2020-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (789, 658, 5112.24, '2023-03-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (330, 646, 9787.04, '2025-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (867, 261, 6040.25, '2022-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (402, 772, 1488.66, '2024-09-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (728, 843, 7430.78, '2020-11-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (876, 298, 7084.05, '2021-06-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (821, 698, 6990.03, '2025-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (500, 527, 1958.15, '2022-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 933, 6119.63, '2024-03-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (758, 891, 2250.45, '2024-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (36, 64, 3881.75, '2023-01-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (436, 665, 640.45, '2024-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (612, 526, 56.77, '2023-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (449, 648, 2394.78, '2022-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (709, 398, 7844.74, '2024-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (627, 545, 8629.21, '2023-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (880, 651, 138.73, '2025-02-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (400, 230, 2151.77, '2021-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (968, 970, 4093.53, '2024-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (405, 626, 2394.97, '2021-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (897, 287, 5607.54, '2022-07-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (286, 957, 8335.37, '2024-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (454, 392, 2871.5, '2022-04-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (941, 213, 898.88, '2020-07-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (975, 571, 7155.85, '2021-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (110, 594, 3958.89, '2021-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (581, 813, 1511.12, '2022-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (4, 487, 4470.72, '2020-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (519, 719, 3753.26, '2024-09-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (142, 234, 891.72, '2025-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (582, 86, 5004.92, '2021-12-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (403, 228, 3852.84, '2023-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (425, 666, 6399.34, '2022-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (809, 102, 2747.9, '2022-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (119, 9, 8385.99, '2023-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (382, 40, 3682.95, '2023-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (890, 948, 5081.19, '2023-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (249, 748, 5000.19, '2020-09-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (408, 808, 9686.9, '2023-12-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (7, 980, 9335.53, '2024-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (516, 311, 1456.02, '2021-04-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (548, 801, 1008.46, '2023-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (767, 705, 2205.3, '2021-02-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (622, 686, 1056.25, '2024-03-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (623, 939, 3948.94, '2021-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (903, 144, 6021.19, '2024-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (778, 385, 5564.04, '2021-12-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (265, 610, 2704.67, '2023-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 102, 7989.4, '2020-05-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (556, 733, 519.82, '2024-01-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (437, 158, 8157.77, '2022-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (733, 176, 8529.9, '2022-09-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 53, 3220.18, '2020-06-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (472, 448, 4845.17, '2021-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (411, 955, 6342.98, '2023-03-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (425, 533, 9006.16, '2021-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (313, 378, 7365.08, '2023-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (817, 426, 435.43, '2021-11-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (89, 906, 1303.66, '2021-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (33, 661, 5590.14, '2021-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (424, 452, 6193.25, '2023-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (172, 596, 5460.86, '2024-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (196, 514, 2664.28, '2025-02-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (335, 73, 6435.1, '2020-04-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (752, 558, 304.0, '2024-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (151, 143, 3798.81, '2024-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (245, 998, 8667.62, '2020-04-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (410, 706, 8087.04, '2024-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (81, 497, 2432.39, '2020-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (238, 220, 4782.52, '2022-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (406, 945, 2997.58, '2022-04-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (856, 290, 7507.85, '2021-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (830, 227, 8857.37, '2022-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (67, 741, 6602.55, '2023-02-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (59, 656, 4317.63, '2022-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (109, 486, 1348.78, '2023-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (611, 540, 3531.46, '2022-09-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (748, 324, 9873.02, '2020-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (897, 281, 1392.99, '2022-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (28, 887, 2565.22, '2024-10-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (380, 982, 1869.44, '2022-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (533, 447, 6181.17, '2024-12-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (504, 573, 580.84, '2023-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (20, 42, 2029.2, '2021-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 622, 2122.9, '2022-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (167, 120, 1216.18, '2023-01-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (75, 943, 9292.34, '2024-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (832, 912, 5652.22, '2021-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (198, 340, 2268.08, '2024-03-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (352, 564, 3313.72, '2023-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (211, 846, 1923.45, '2020-09-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (568, 926, 395.26, '2021-10-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (81, 836, 3099.16, '2024-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (176, 728, 5418.54, '2024-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (401, 153, 2618.86, '2023-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (741, 98, 3894.49, '2022-04-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (236, 972, 8004.31, '2025-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (944, 549, 1562.73, '2024-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (238, 176, 1920.46, '2020-10-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (317, 163, 6074.03, '2024-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (379, 756, 6869.49, '2021-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (769, 87, 9015.07, '2022-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (804, 647, 4023.99, '2022-01-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (129, 468, 7088.68, '2022-07-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (893, 740, 9443.88, '2022-02-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (383, 364, 971.72, '2024-02-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (981, 310, 8716.51, '2024-05-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (684, 357, 4643.31, '2024-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (924, 545, 4960.29, '2020-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (829, 434, 2136.56, '2022-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (22, 643, 4435.65, '2021-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (657, 774, 7598.92, '2023-06-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (692, 759, 7066.16, '2022-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (577, 403, 5143.9, '2022-07-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (365, 362, 1624.3, '2023-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (805, 9, 3846.97, '2022-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (669, 602, 6976.42, '2023-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (421, 525, 3062.57, '2022-11-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (342, 775, 5610.59, '2022-10-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (553, 754, 1157.26, '2021-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (817, 389, 6629.62, '2024-07-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 279, 8992.5, '2020-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (676, 138, 3045.06, '2021-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (643, 899, 962.92, '2021-02-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (421, 826, 8255.17, '2023-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (596, 393, 3492.63, '2022-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 305, 5030.76, '2024-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (605, 351, 4339.07, '2024-11-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (112, 895, 6175.37, '2024-08-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (693, 103, 4737.84, '2025-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (313, 699, 3045.94, '2024-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (499, 111, 2310.33, '2020-04-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (468, 529, 4536.88, '2020-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (131, 779, 4859.38, '2020-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (196, 608, 4643.92, '2021-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (495, 971, 6778.97, '2024-06-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (15, 13, 9990.24, '2024-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (918, 353, 4884.86, '2022-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (247, 316, 2747.85, '2023-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (470, 161, 1117.91, '2020-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (333, 976, 662.45, '2023-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (84, 198, 5800.09, '2022-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (548, 970, 4761.17, '2020-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (694, 369, 20.04, '2021-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (566, 252, 7022.42, '2024-04-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (467, 131, 3820.18, '2021-05-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (445, 621, 6586.04, '2025-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (870, 79, 1344.01, '2020-11-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (765, 658, 7306.37, '2022-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (404, 477, 2520.69, '2020-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (139, 76, 2123.48, '2024-08-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (44, 457, 2297.93, '2024-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (911, 824, 9523.57, '2024-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (236, 850, 7539.75, '2025-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (304, 195, 5741.96, '2022-04-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (581, 333, 1389.47, '2023-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (495, 555, 5878.24, '2022-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (934, 35, 6341.31, '2023-07-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (6, 147, 434.58, '2020-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (10, 236, 5769.59, '2023-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (724, 611, 4010.37, '2023-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 335, 8609.19, '2020-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (40, 236, 2851.07, '2020-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (380, 931, 4105.29, '2020-07-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (933, 221, 6555.26, '2021-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (332, 764, 1546.09, '2022-09-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (40, 960, 1615.56, '2021-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (335, 277, 3343.01, '2021-05-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (51, 131, 5737.88, '2024-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (12, 407, 7985.28, '2024-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (378, 704, 3102.24, '2021-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (815, 551, 52.81, '2024-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (38, 828, 2685.46, '2024-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (186, 933, 6167.86, '2022-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (552, 725, 5833.05, '2024-05-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (762, 127, 6569.81, '2023-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (854, 37, 144.09, '2020-03-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (425, 278, 993.08, '2020-12-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (416, 149, 6699.24, '2023-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (525, 495, 8665.58, '2023-04-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (990, 352, 3247.1, '2024-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (331, 53, 8934.64, '2021-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (436, 212, 2631.22, '2022-09-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (638, 821, 886.08, '2024-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (976, 66, 8196.32, '2024-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (755, 73, 3167.25, '2021-09-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (892, 712, 4198.77, '2021-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (337, 111, 3278.36, '2025-01-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (161, 328, 5422.3, '2022-01-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (527, 765, 8634.86, '2020-07-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (473, 947, 2925.22, '2023-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (115, 608, 4140.84, '2020-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (82, 958, 5237.09, '2022-07-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (994, 887, 2765.9, '2021-06-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (534, 986, 7638.22, '2020-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (816, 301, 474.45, '2024-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (671, 383, 8543.21, '2024-05-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (869, 444, 5844.12, '2021-09-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (995, 381, 6734.98, '2023-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (85, 586, 2095.39, '2020-06-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (470, 156, 7831.38, '2022-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (45, 457, 2784.92, '2021-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (653, 729, 6740.27, '2021-03-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (541, 680, 7249.51, '2020-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (376, 562, 5215.49, '2023-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (864, 171, 3837.7, '2022-07-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (278, 252, 2649.95, '2022-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (87, 802, 165.84, '2022-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (757, 999, 2439.5, '2021-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (294, 600, 8035.99, '2021-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (407, 549, 7324.85, '2021-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (981, 961, 7975.56, '2021-05-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (860, 74, 581.7, '2021-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (923, 216, 3567.19, '2021-05-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (61, 631, 3925.29, '2022-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (389, 219, 8507.89, '2021-04-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (349, 241, 2135.85, '2021-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (976, 282, 7346.16, '2021-06-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 219, 6961.83, '2022-11-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (669, 449, 1146.68, '2024-12-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (372, 834, 4458.37, '2021-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (173, 493, 6276.51, '2021-04-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (251, 153, 6676.65, '2024-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 587, 8660.88, '2022-07-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (87, 471, 7616.38, '2023-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (422, 573, 4865.37, '2020-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (615, 274, 9887.04, '2021-12-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (490, 472, 2942.12, '2021-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (760, 113, 8596.1, '2021-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (203, 36, 869.34, '2021-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (390, 760, 1526.59, '2022-06-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (717, 921, 2225.3, '2023-10-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (216, 909, 163.22, '2020-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (442, 534, 7619.52, '2025-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (898, 389, 5230.92, '2020-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (259, 796, 3795.95, '2023-08-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (532, 936, 5446.11, '2023-07-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (317, 227, 6311.23, '2021-03-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (370, 744, 728.09, '2024-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (289, 673, 7710.14, '2022-05-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (530, 497, 1915.97, '2023-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (427, 301, 422.41, '2022-07-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (767, 359, 5428.02, '2021-03-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (301, 467, 1462.42, '2024-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (799, 547, 773.86, '2024-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (142, 618, 4040.52, '2025-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (685, 852, 9648.6, '2023-04-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (870, 200, 5944.02, '2024-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (495, 535, 6519.22, '2022-06-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 33, 2433.52, '2021-01-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (602, 905, 2580.94, '2021-04-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (465, 683, 7497.84, '2023-02-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (948, 525, 1063.33, '2020-06-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (141, 687, 8640.72, '2022-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (407, 957, 6748.04, '2021-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (504, 31, 1444.14, '2023-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (358, 895, 2098.54, '2021-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (90, 3, 8461.8, '2022-03-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (788, 963, 2412.15, '2021-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (891, 252, 330.23, '2025-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (307, 553, 5476.01, '2022-01-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (555, 549, 1530.46, '2023-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (619, 480, 6675.02, '2022-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (340, 764, 8121.42, '2024-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (95, 485, 9810.34, '2022-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (229, 373, 5667.75, '2022-06-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (514, 74, 2808.55, '2021-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (5, 938, 7078.85, '2022-09-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (352, 229, 9419.26, '2024-01-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (710, 832, 4202.75, '2024-04-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (100, 259, 7008.33, '2021-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (858, 231, 9523.1, '2024-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (457, 147, 8051.83, '2024-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (226, 99, 6701.99, '2022-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (984, 968, 9548.19, '2020-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (77, 326, 6912.52, '2021-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (123, 552, 6633.4, '2020-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (760, 354, 4962.68, '2020-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (758, 582, 7158.51, '2023-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (978, 966, 2458.42, '2022-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (976, 753, 8862.14, '2022-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 441, 3795.13, '2020-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (402, 918, 4183.47, '2020-06-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (973, 180, 2338.39, '2024-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (109, 238, 2309.3, '2022-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (990, 17, 9781.54, '2023-08-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (594, 513, 6315.94, '2024-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (174, 114, 4012.8, '2021-08-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (114, 338, 4917.71, '2022-10-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (371, 879, 4865.54, '2024-05-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (757, 522, 6752.32, '2024-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (984, 33, 9838.65, '2023-06-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (353, 31, 4146.72, '2020-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (381, 230, 1947.15, '2021-11-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (25, 854, 5805.21, '2023-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (127, 666, 6964.81, '2023-04-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (375, 412, 1789.47, '2020-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (45, 419, 6093.53, '2021-02-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (448, 457, 696.28, '2020-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (837, 55, 4249.74, '2023-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 584, 252.11, '2023-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (417, 847, 1071.98, '2020-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (242, 497, 8687.05, '2024-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (791, 115, 2505.48, '2024-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (31, 276, 2203.25, '2024-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (331, 450, 2394.4, '2023-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (579, 646, 4035.45, '2022-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (829, 768, 3301.42, '2021-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (360, 256, 7718.43, '2020-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (480, 585, 1538.3, '2024-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (622, 380, 4872.4, '2022-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (734, 704, 7305.85, '2022-01-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 918, 7911.0, '2024-12-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (721, 755, 1486.44, '2024-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (326, 465, 3143.25, '2020-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (141, 953, 5085.65, '2021-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (471, 729, 5425.12, '2023-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (937, 922, 7702.03, '2021-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (306, 377, 9286.61, '2021-12-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (821, 871, 6199.01, '2021-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (643, 17, 9131.11, '2024-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (834, 804, 981.5, '2024-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (89, 484, 254.14, '2022-09-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (374, 100, 3151.34, '2020-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (549, 375, 3248.3, '2022-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (619, 411, 4611.37, '2024-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (696, 415, 1754.28, '2023-01-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (994, 921, 2386.01, '2021-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 506, 3188.25, '2020-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (625, 584, 947.39, '2023-01-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (889, 859, 275.0, '2023-04-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (573, 639, 3350.82, '2023-09-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (409, 473, 4057.47, '2022-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 904, 5867.18, '2022-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (360, 635, 2172.47, '2022-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (866, 764, 2220.02, '2022-05-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (796, 109, 1586.31, '2023-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (81, 214, 1166.69, '2025-02-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (614, 430, 3150.32, '2022-11-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (224, 806, 4804.0, '2021-06-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (316, 248, 2682.71, '2024-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (200, 568, 5611.0, '2024-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (698, 220, 275.38, '2024-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (731, 497, 5579.13, '2021-03-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (177, 404, 9234.72, '2022-09-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (800, 343, 6764.99, '2020-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 324, 7331.7, '2024-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (94, 331, 333.49, '2022-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (459, 177, 7166.49, '2021-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (639, 738, 9879.71, '2024-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (645, 936, 9424.9, '2022-06-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (516, 823, 2052.08, '2023-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (958, 842, 9610.92, '2024-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (294, 546, 2739.04, '2025-02-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 202, 932.25, '2023-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (798, 17, 2030.14, '2023-02-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (710, 437, 498.72, '2023-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (363, 725, 888.96, '2021-10-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (817, 22, 9524.85, '2022-01-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (671, 219, 1031.22, '2022-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (768, 769, 1496.33, '2021-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (401, 779, 7224.37, '2023-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (457, 905, 5729.97, '2021-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (9, 706, 1526.86, '2022-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (188, 955, 322.67, '2022-04-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (809, 861, 1408.18, '2023-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (4, 369, 1237.58, '2020-11-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (11, 727, 1886.36, '2022-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (860, 748, 7523.17, '2023-05-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (920, 837, 2848.96, '2022-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (681, 559, 8388.64, '2022-12-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (428, 670, 4636.17, '2020-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (51, 327, 2651.6, '2021-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (201, 815, 5332.65, '2023-01-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (18, 367, 6239.56, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (209, 672, 6161.07, '2023-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (63, 344, 4288.25, '2025-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (137, 688, 8341.33, '2020-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (386, 956, 8376.3, '2020-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (667, 378, 5922.14, '2023-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (249, 833, 2676.21, '2023-04-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (676, 475, 365.34, '2020-04-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (188, 114, 2547.88, '2020-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (393, 67, 7214.89, '2022-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (665, 279, 4961.54, '2023-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (951, 435, 2455.8, '2025-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 572, 3578.99, '2024-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (360, 663, 8799.81, '2023-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (994, 396, 6712.89, '2024-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 126, 7430.71, '2023-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (736, 653, 3184.06, '2023-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (977, 72, 7084.25, '2021-09-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (128, 927, 3206.38, '2021-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (728, 588, 2094.44, '2022-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (131, 54, 7896.28, '2023-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (83, 374, 6046.6, '2022-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (746, 714, 2634.87, '2022-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (988, 183, 4746.7, '2022-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (78, 818, 5708.18, '2020-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (839, 954, 8751.57, '2021-02-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (119, 523, 8897.06, '2023-06-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (461, 188, 4575.18, '2023-08-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (183, 485, 639.27, '2021-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (648, 435, 2743.19, '2020-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (427, 417, 5263.33, '2024-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (196, 24, 5011.15, '2021-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (874, 274, 7895.38, '2024-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (488, 563, 276.7, '2023-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (541, 770, 1723.89, '2021-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (568, 188, 3097.28, '2020-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (276, 7, 5223.28, '2025-01-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (199, 696, 5199.86, '2024-05-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (754, 143, 1925.45, '2021-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (443, 770, 2484.0, '2024-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (630, 938, 7330.32, '2022-06-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (587, 743, 9008.54, '2022-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 883, 1702.38, '2024-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (732, 522, 3103.9, '2024-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (765, 540, 8294.73, '2023-05-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (823, 389, 7991.98, '2023-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (479, 282, 5490.52, '2024-11-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (15, 117, 2212.04, '2025-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (101, 836, 9301.39, '2022-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (315, 210, 5432.82, '2024-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (200, 456, 3726.42, '2023-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (797, 421, 8842.47, '2021-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (660, 525, 4829.06, '2023-03-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (128, 770, 229.13, '2021-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (933, 593, 377.81, '2020-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (91, 877, 4292.11, '2024-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (526, 446, 249.23, '2021-02-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (17, 308, 8983.05, '2020-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (935, 954, 3737.46, '2023-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (163, 166, 3500.89, '2023-12-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (90, 244, 2356.19, '2023-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (96, 113, 4656.82, '2021-06-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (300, 48, 4464.23, '2022-03-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (132, 545, 7116.5, '2020-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (136, 427, 3510.87, '2022-12-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (426, 57, 2980.38, '2022-08-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (886, 694, 6536.37, '2023-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (69, 6, 7097.17, '2021-10-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (67, 529, 4223.47, '2021-11-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (650, 291, 4022.74, '2021-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (801, 612, 4084.84, '2024-07-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (669, 39, 3365.83, '2024-11-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 167, 6436.56, '2022-11-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (77, 829, 5749.85, '2021-10-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (208, 785, 1660.31, '2023-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (42, 437, 1034.85, '2024-07-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (519, 457, 7335.57, '2020-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (673, 872, 8434.74, '2023-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (7, 451, 4300.29, '2022-08-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (520, 532, 3914.47, '2023-03-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (607, 6, 4311.53, '2022-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (872, 925, 2448.01, '2024-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (364, 877, 4860.0, '2020-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (322, 736, 2204.25, '2021-12-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (192, 719, 3105.95, '2024-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (130, 909, 5186.89, '2021-06-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (355, 249, 910.69, '2020-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (772, 460, 8042.77, '2021-07-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (74, 99, 1601.88, '2022-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (816, 902, 816.94, '2021-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (964, 315, 9250.55, '2023-10-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (353, 655, 4844.8, '2021-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (294, 903, 4862.47, '2021-06-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (674, 472, 9929.46, '2022-07-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (162, 251, 8735.59, '2022-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (513, 639, 6827.67, '2023-01-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (478, 420, 417.64, '2021-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (132, 13, 1015.63, '2024-02-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (708, 341, 4177.56, '2023-03-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (514, 865, 5078.49, '2023-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (828, 859, 1453.31, '2022-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (711, 741, 7156.18, '2021-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (322, 17, 417.79, '2022-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (918, 10, 8008.26, '2020-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (678, 434, 7781.5, '2021-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (452, 484, 7831.41, '2024-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (442, 752, 6708.86, '2022-03-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 708, 479.78, '2024-03-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (473, 435, 4998.41, '2022-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (439, 944, 3260.65, '2024-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (631, 840, 4681.06, '2022-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (63, 660, 6563.28, '2022-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (661, 704, 2787.34, '2022-07-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (452, 581, 3552.67, '2020-11-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (803, 523, 2171.78, '2024-02-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (819, 256, 195.44, '2025-01-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (35, 798, 457.94, '2022-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (560, 162, 3179.06, '2020-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (305, 108, 5599.73, '2021-04-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 178, 9821.14, '2024-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (603, 955, 3833.33, '2024-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (124, 61, 162.74, '2020-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (330, 490, 8835.3, '2024-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (619, 750, 906.73, '2020-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (576, 804, 232.34, '2024-12-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (235, 677, 1097.15, '2021-02-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (796, 345, 2406.49, '2021-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (67, 439, 712.67, '2020-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (332, 492, 1700.16, '2022-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (930, 243, 6211.17, '2024-06-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (191, 740, 2575.09, '2020-12-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (687, 752, 1738.69, '2021-11-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (175, 879, 1742.43, '2021-12-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (392, 481, 914.18, '2022-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (92, 916, 4701.53, '2024-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (303, 987, 1520.82, '2022-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (842, 75, 8190.4, '2023-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (895, 292, 1849.76, '2024-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 98, 6986.35, '2020-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (686, 678, 4706.62, '2023-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (735, 730, 6466.19, '2022-10-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (772, 180, 1299.68, '2023-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (945, 22, 4460.27, '2020-09-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (66, 780, 6914.69, '2021-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (607, 902, 5436.43, '2023-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (245, 326, 2822.12, '2020-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (863, 772, 3558.47, '2020-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (254, 412, 6700.95, '2020-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (340, 842, 9094.26, '2021-01-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (223, 71, 5132.97, '2023-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (103, 291, 2135.46, '2023-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (801, 447, 9367.85, '2022-05-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (147, 448, 1028.84, '2020-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (668, 598, 7904.24, '2025-02-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (19, 367, 2806.71, '2021-10-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (926, 163, 8336.52, '2024-11-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (951, 706, 6753.28, '2024-03-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (812, 501, 3271.26, '2021-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 493, 9460.39, '2024-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (130, 676, 1052.44, '2020-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (751, 690, 8662.27, '2021-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (665, 736, 773.06, '2021-08-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (867, 58, 2100.78, '2023-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (284, 477, 336.88, '2024-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (789, 228, 168.76, '2022-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (48, 41, 7971.57, '2020-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (702, 161, 8894.35, '2020-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (810, 230, 6956.27, '2021-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (17, 166, 7298.3, '2022-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (628, 307, 8667.7, '2024-12-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (890, 421, 2316.39, '2021-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (253, 786, 3499.18, '2022-07-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (901, 617, 7268.27, '2020-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (41, 148, 572.29, '2023-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (657, 234, 4130.47, '2023-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (893, 641, 568.94, '2021-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (843, 213, 629.27, '2024-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (304, 88, 7519.96, '2020-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 933, 206.22, '2020-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (163, 836, 3712.33, '2024-05-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (663, 503, 4120.31, '2022-04-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (429, 57, 2383.48, '2023-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (916, 635, 4615.41, '2024-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (901, 904, 3962.51, '2020-11-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (966, 651, 3658.76, '2021-11-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (364, 44, 4273.25, '2023-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (565, 268, 5180.45, '2023-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (974, 197, 2246.13, '2020-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (490, 653, 3304.2, '2023-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 389, 6894.94, '2020-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (692, 829, 5432.08, '2020-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 569, 1396.43, '2024-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (429, 806, 3406.15, '2023-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (263, 463, 1552.88, '2021-10-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (295, 962, 5908.52, '2022-02-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (431, 462, 7603.12, '2022-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (499, 936, 4587.75, '2023-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (36, 729, 4821.28, '2021-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (321, 817, 9663.6, '2024-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (502, 347, 896.78, '2022-07-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (860, 806, 7570.74, '2020-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (200, 584, 3419.36, '2023-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (869, 35, 2507.04, '2022-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (697, 914, 6081.68, '2020-05-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (625, 747, 9044.25, '2022-07-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 343, 6393.78, '2024-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (187, 844, 128.79, '2024-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (312, 348, 9101.96, '2023-08-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (109, 389, 7961.42, '2020-09-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (80, 373, 444.37, '2022-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (853, 760, 1565.56, '2024-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (106, 113, 4041.15, '2025-02-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (821, 494, 2091.86, '2021-07-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (40, 959, 4849.84, '2020-07-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (179, 443, 8285.42, '2023-06-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (426, 826, 5900.42, '2023-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (578, 461, 6618.66, '2022-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (613, 806, 1400.8, '2025-01-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (443, 686, 7120.08, '2024-07-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 120, 6253.8, '2024-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (972, 157, 5781.15, '2023-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (2, 496, 1074.35, '2022-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (113, 468, 1856.15, '2022-12-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (771, 241, 674.05, '2020-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (751, 854, 6729.86, '2023-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (261, 824, 299.53, '2024-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (111, 975, 3583.91, '2023-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (553, 686, 9749.27, '2020-12-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (535, 454, 7397.73, '2020-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 991, 1784.18, '2023-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (959, 594, 1209.44, '2023-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (731, 136, 5117.61, '2022-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (33, 211, 6124.64, '2021-01-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (537, 175, 8176.17, '2022-10-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (930, 204, 6761.5, '2021-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (796, 537, 7139.63, '2021-09-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (472, 579, 6786.22, '2024-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (524, 429, 7152.64, '2020-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (827, 934, 7663.44, '2021-12-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (46, 630, 7555.36, '2021-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (427, 452, 5329.78, '2025-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (151, 737, 1778.73, '2021-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (72, 814, 6221.25, '2020-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (255, 127, 7498.63, '2023-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (614, 674, 6702.07, '2021-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (545, 217, 9668.89, '2024-08-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (894, 18, 2311.49, '2024-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (909, 623, 8347.01, '2021-04-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (739, 831, 2471.14, '2024-03-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (779, 51, 442.33, '2022-07-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (51, 962, 1857.19, '2020-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (359, 475, 2039.26, '2021-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (960, 800, 6271.71, '2023-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (37, 411, 7980.98, '2024-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 372, 3934.91, '2023-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (152, 735, 3263.02, '2024-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (345, 993, 3556.26, '2021-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (746, 962, 2567.3, '2023-06-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (304, 98, 2285.55, '2023-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (416, 552, 7479.65, '2021-12-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (584, 720, 6695.58, '2022-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 387, 4153.98, '2022-03-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (63, 355, 7480.42, '2021-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (10, 131, 3947.33, '2022-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (848, 8, 2049.27, '2021-10-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (647, 249, 2583.63, '2024-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (564, 317, 5826.27, '2025-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (933, 980, 8389.49, '2023-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (549, 414, 7683.34, '2021-11-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (606, 612, 3755.09, '2022-01-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (657, 360, 1412.26, '2024-02-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (739, 489, 7089.67, '2021-02-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (83, 321, 8830.74, '2021-07-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (622, 952, 8598.92, '2020-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (201, 519, 2599.25, '2023-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (706, 753, 7123.4, '2023-06-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (62, 772, 4496.66, '2023-11-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (116, 272, 8740.68, '2024-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (810, 74, 7604.85, '2025-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (948, 305, 6857.72, '2023-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 710, 5446.7, '2021-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 709, 3300.0, '2024-05-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (895, 181, 3962.37, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (490, 491, 8574.54, '2020-09-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (504, 977, 4539.01, '2023-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (863, 979, 149.23, '2021-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (268, 596, 7392.0, '2021-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (210, 529, 1338.92, '2021-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (217, 20, 9483.09, '2023-01-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (142, 207, 8677.14, '2023-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (49, 65, 3925.48, '2024-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (559, 94, 2522.37, '2023-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (561, 107, 3940.18, '2022-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (828, 309, 2410.48, '2020-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (503, 526, 4497.17, '2021-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (649, 382, 8305.94, '2023-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (809, 536, 5614.67, '2022-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (622, 834, 3056.28, '2020-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (724, 471, 2184.02, '2024-03-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (700, 972, 3989.42, '2021-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (387, 277, 1847.56, '2020-04-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (869, 499, 8550.06, '2020-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (989, 611, 1636.46, '2024-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (424, 457, 2605.45, '2022-04-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (291, 930, 6012.9, '2022-03-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (856, 281, 9757.15, '2023-09-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (357, 400, 161.61, '2020-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (453, 236, 9864.88, '2021-03-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (81, 210, 3198.93, '2023-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (639, 526, 227.46, '2023-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (646, 431, 4035.38, '2020-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (327, 605, 9237.75, '2022-08-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (557, 802, 2385.31, '2024-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 743, 8727.09, '2021-08-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (685, 21, 8903.21, '2024-09-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (828, 607, 5225.5, '2021-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (517, 13, 1930.54, '2021-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (78, 872, 8512.25, '2023-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (71, 69, 6462.02, '2021-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (529, 279, 9325.39, '2024-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (938, 252, 3016.13, '2022-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (830, 6, 8368.36, '2022-07-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (466, 151, 5311.84, '2024-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 764, 1941.33, '2024-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (826, 558, 9723.22, '2022-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (992, 25, 1627.96, '2021-10-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (120, 858, 8896.15, '2020-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (158, 642, 8706.28, '2023-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (389, 286, 9237.3, '2020-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (175, 463, 6950.31, '2020-09-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (8, 264, 42.76, '2023-05-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (405, 104, 9895.5, '2022-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (486, 404, 2054.64, '2022-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 528, 5290.13, '2024-01-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (665, 329, 7841.08, '2021-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (113, 930, 2596.95, '2024-01-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (164, 308, 7167.87, '2021-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (344, 857, 7618.19, '2021-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (738, 478, 1473.07, '2025-01-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (396, 617, 7265.62, '2020-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (293, 553, 1781.78, '2023-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (586, 789, 406.41, '2022-09-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (13, 571, 4745.38, '2024-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (307, 419, 1709.62, '2025-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (144, 744, 3950.12, '2022-01-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (661, 843, 6183.6, '2024-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (793, 818, 7812.58, '2020-09-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 512, 531.07, '2022-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (175, 552, 1748.3, '2022-04-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (943, 799, 1773.69, '2020-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (614, 657, 1793.8, '2022-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (183, 121, 2100.26, '2021-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (325, 941, 7187.97, '2024-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (598, 822, 9866.33, '2024-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 660, 2848.87, '2023-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (235, 456, 6781.99, '2021-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (199, 44, 9582.77, '2020-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (106, 165, 6954.16, '2021-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (68, 989, 7067.13, '2020-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (695, 487, 2970.99, '2022-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (430, 745, 2044.75, '2021-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (8, 1000, 6015.37, '2020-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (722, 876, 7598.33, '2024-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (487, 21, 637.1, '2021-04-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (5, 182, 2344.34, '2021-05-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (971, 832, 5179.11, '2020-07-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (124, 611, 4527.1, '2021-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (170, 575, 1736.16, '2024-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (818, 513, 1537.17, '2024-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (812, 605, 3505.18, '2023-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (579, 152, 2817.74, '2020-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (175, 770, 7492.24, '2023-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (367, 389, 3724.37, '2022-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (95, 851, 3819.24, '2021-02-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (519, 173, 7033.68, '2022-10-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (327, 61, 3166.26, '2022-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (242, 505, 961.99, '2021-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (937, 286, 3683.44, '2021-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (642, 875, 8866.59, '2020-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (818, 342, 2285.61, '2020-09-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (207, 369, 8795.88, '2023-10-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (725, 475, 9297.89, '2023-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 869, 2814.26, '2024-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (954, 113, 6142.72, '2024-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (362, 977, 4920.18, '2021-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 815, 2244.49, '2025-01-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (226, 328, 93.29, '2021-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (89, 473, 3899.8, '2021-05-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 789, 3107.56, '2023-05-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (649, 293, 395.63, '2022-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (65, 322, 1369.73, '2021-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (455, 225, 1093.96, '2023-11-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (901, 605, 0.52, '2021-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (767, 957, 5002.92, '2023-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (373, 443, 2862.94, '2024-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (280, 432, 4918.54, '2020-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (711, 313, 2880.29, '2022-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (664, 506, 933.16, '2021-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (468, 360, 6387.85, '2024-11-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (9, 133, 36.56, '2021-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (147, 562, 5573.48, '2023-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (951, 361, 8397.69, '2021-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (181, 605, 3158.2, '2022-03-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (826, 932, 9916.64, '2022-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (449, 235, 5655.89, '2024-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (590, 961, 687.02, '2021-01-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (728, 84, 2515.64, '2024-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (41, 345, 4532.19, '2021-08-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (359, 93, 2101.72, '2023-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (79, 348, 47.76, '2021-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (365, 184, 7175.8, '2024-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (4, 71, 7701.63, '2020-12-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (342, 974, 4813.07, '2023-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (615, 11, 3020.87, '2021-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (508, 254, 8872.04, '2023-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 919, 4002.97, '2022-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (251, 677, 3389.21, '2022-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (796, 1000, 8252.02, '2022-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (338, 825, 8851.64, '2021-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (379, 299, 8341.42, '2020-10-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (467, 236, 8878.72, '2023-03-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (287, 728, 9429.18, '2024-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (680, 830, 3463.93, '2020-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (274, 267, 3313.35, '2021-10-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (772, 265, 7966.39, '2020-06-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (65, 761, 3295.41, '2022-02-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (764, 234, 553.13, '2022-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (305, 519, 9002.09, '2020-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (173, 383, 5781.39, '2023-08-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (76, 408, 7783.08, '2024-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (155, 9, 5225.6, '2024-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (249, 743, 5180.4, '2022-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (547, 996, 2208.77, '2023-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (418, 240, 2757.67, '2025-02-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (145, 75, 7860.75, '2020-10-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (823, 361, 5374.27, '2024-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (347, 318, 9873.76, '2022-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (343, 171, 3281.53, '2023-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (376, 229, 4387.5, '2024-10-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (566, 139, 5160.7, '2023-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (997, 826, 7358.65, '2022-12-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (306, 500, 1313.3, '2022-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (254, 86, 2596.64, '2020-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (1, 342, 3748.86, '2022-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (839, 539, 4256.71, '2023-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (190, 504, 4446.87, '2024-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (317, 450, 4442.5, '2021-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (592, 702, 3033.7, '2020-05-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (713, 228, 5003.83, '2024-05-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (863, 667, 6363.14, '2021-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (894, 374, 3315.91, '2021-06-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (371, 85, 9629.35, '2021-04-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (241, 495, 7352.78, '2024-07-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (389, 855, 3988.74, '2025-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (669, 602, 2787.3, '2021-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (845, 546, 578.63, '2023-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (22, 700, 2504.05, '2024-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (889, 120, 4520.84, '2022-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (694, 709, 1284.15, '2022-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (842, 565, 8842.54, '2024-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (652, 290, 2815.12, '2021-06-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (112, 339, 1714.47, '2022-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (177, 102, 8620.11, '2023-11-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (779, 758, 1831.83, '2022-08-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (733, 584, 4322.29, '2020-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (55, 818, 4647.37, '2023-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (278, 587, 6903.4, '2023-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (682, 616, 218.62, '2023-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (303, 287, 6732.84, '2024-06-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (810, 742, 5957.51, '2022-12-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (100, 862, 8776.67, '2021-07-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (418, 527, 6974.29, '2025-01-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (269, 304, 4531.46, '2023-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (496, 762, 2852.16, '2024-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 822, 7887.0, '2021-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (800, 981, 3685.38, '2022-01-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (681, 963, 8080.65, '2024-07-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (566, 997, 3413.05, '2020-07-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (266, 784, 1495.67, '2023-09-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (174, 301, 8939.64, '2022-11-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (764, 314, 7322.64, '2023-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (141, 700, 4098.29, '2024-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (914, 571, 6840.51, '2021-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 143, 2456.74, '2023-11-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (371, 447, 3137.72, '2025-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (739, 959, 8431.58, '2023-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (905, 593, 1082.69, '2024-12-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (536, 426, 3524.13, '2022-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (356, 397, 6420.82, '2023-12-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (429, 440, 9417.21, '2020-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (192, 563, 9028.15, '2021-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (204, 248, 4638.18, '2021-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (890, 341, 9865.85, '2023-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 49, 4865.22, '2022-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (350, 603, 9261.31, '2022-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (405, 709, 3657.77, '2025-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (613, 411, 821.11, '2024-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (692, 493, 3495.57, '2021-04-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (964, 869, 1541.46, '2020-05-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (401, 563, 6102.24, '2021-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (749, 205, 5926.61, '2021-07-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (973, 579, 1505.14, '2021-08-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (216, 540, 956.26, '2024-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (189, 685, 8047.34, '2025-01-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (218, 462, 4489.74, '2022-08-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (132, 5, 6119.19, '2021-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (368, 104, 3891.7, '2023-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 977, 3377.35, '2020-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (895, 708, 5924.84, '2023-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (361, 875, 4571.51, '2023-11-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (364, 439, 3198.72, '2023-07-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (520, 769, 2797.76, '2024-09-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (410, 935, 326.04, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (786, 954, 2831.8, '2020-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (284, 311, 1753.29, '2022-07-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (666, 553, 6955.46, '2023-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (460, 372, 4752.82, '2020-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (742, 995, 2664.46, '2024-10-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (984, 491, 7711.4, '2021-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (443, 434, 8996.23, '2025-03-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (328, 691, 683.93, '2023-08-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (701, 437, 8443.51, '2024-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (926, 814, 2840.9, '2022-04-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (126, 363, 3106.28, '2022-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (567, 509, 9069.8, '2024-06-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (35, 315, 4719.18, '2022-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (116, 416, 8835.9, '2024-02-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (445, 820, 7368.58, '2022-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (434, 736, 7348.57, '2021-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (716, 855, 6754.94, '2022-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (462, 554, 8007.57, '2022-02-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (671, 255, 192.38, '2022-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (962, 944, 526.37, '2022-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (784, 346, 4140.34, '2021-02-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (218, 601, 7143.99, '2021-10-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (977, 776, 6899.89, '2023-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (92, 302, 3015.41, '2024-02-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (836, 868, 3595.87, '2020-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (842, 913, 3301.75, '2022-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (462, 486, 1863.3, '2023-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (12, 395, 5242.48, '2020-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (978, 375, 7124.5, '2022-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (131, 403, 4873.96, '2021-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (547, 40, 3068.04, '2021-05-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (329, 405, 623.22, '2023-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (654, 401, 732.49, '2022-12-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (488, 284, 3886.46, '2020-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (880, 503, 6783.11, '2024-11-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (174, 788, 8179.01, '2023-07-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (145, 402, 3655.88, '2021-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (758, 393, 4343.23, '2021-10-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (444, 240, 1224.58, '2022-03-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (698, 114, 7426.16, '2023-07-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (219, 765, 3672.62, '2022-01-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (302, 10, 6096.09, '2023-04-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (832, 374, 8021.14, '2022-08-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (80, 385, 9475.84, '2024-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (849, 581, 9114.47, '2024-10-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (450, 751, 1917.94, '2022-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (376, 487, 6953.8, '2023-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (723, 560, 9819.01, '2023-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (384, 547, 8126.43, '2024-07-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (172, 668, 3339.98, '2021-09-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (391, 117, 5890.35, '2024-07-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (519, 209, 2320.9, '2022-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (569, 79, 9077.53, '2020-07-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (205, 167, 3981.01, '2024-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (782, 428, 4867.73, '2021-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (384, 870, 8406.98, '2022-04-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (795, 982, 4281.81, '2020-04-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (987, 68, 5813.78, '2023-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (220, 183, 342.11, '2024-01-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (984, 331, 8520.52, '2020-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (155, 564, 4709.89, '2020-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (605, 55, 156.5, '2024-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (266, 530, 5831.95, '2021-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (572, 571, 7327.91, '2024-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (705, 997, 2556.2, '2021-06-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (67, 301, 6313.31, '2022-02-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (602, 688, 6121.57, '2021-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (348, 149, 2886.26, '2022-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (883, 670, 3522.4, '2024-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (226, 56, 2314.07, '2022-08-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (928, 921, 3620.24, '2024-07-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (586, 709, 5908.48, '2022-03-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (764, 426, 5738.98, '2021-04-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (164, 338, 4174.75, '2021-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (173, 385, 214.67, '2022-04-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (734, 415, 5827.85, '2024-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (736, 421, 2036.69, '2020-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (408, 747, 3549.63, '2022-02-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (797, 848, 9585.19, '2022-10-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (24, 751, 9531.89, '2022-05-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (708, 630, 580.7, '2020-05-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (212, 558, 1874.27, '2023-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (955, 451, 9007.93, '2024-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (585, 924, 779.04, '2020-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (71, 246, 499.06, '2025-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (883, 542, 6247.75, '2024-05-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (196, 114, 5365.51, '2024-02-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (478, 745, 6156.84, '2021-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (84, 266, 8861.27, '2024-10-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (344, 960, 1249.09, '2023-04-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (326, 610, 8046.81, '2025-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (884, 419, 2119.92, '2022-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (234, 620, 8033.37, '2023-06-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (528, 137, 8144.34, '2020-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (11, 915, 8346.16, '2020-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (693, 315, 6136.5, '2021-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (240, 788, 5680.89, '2020-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (463, 717, 7794.47, '2025-01-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (862, 103, 363.18, '2020-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (769, 571, 7805.86, '2023-09-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (293, 410, 8507.65, '2023-02-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (620, 355, 3731.28, '2021-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (106, 39, 9179.76, '2023-01-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (170, 76, 5142.07, '2022-12-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (391, 424, 8832.19, '2024-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (508, 398, 917.15, '2024-03-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (280, 633, 7048.34, '2022-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (671, 973, 5763.26, '2023-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (724, 851, 6935.1, '2023-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (208, 921, 851.65, '2022-02-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (385, 823, 1628.4, '2022-01-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (378, 519, 2555.36, '2024-08-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (152, 837, 215.92, '2020-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (513, 522, 4815.15, '2022-11-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (811, 505, 8249.28, '2021-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (333, 66, 5072.78, '2021-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (553, 494, 2698.42, '2020-11-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (973, 836, 6604.71, '2020-08-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (902, 481, 883.88, '2023-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (244, 616, 286.8, '2020-06-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (719, 254, 9884.58, '2023-03-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (606, 982, 6431.2, '2020-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (673, 372, 8748.34, '2022-02-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (631, 941, 6456.55, '2020-11-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (161, 15, 8048.89, '2023-02-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (841, 447, 7120.44, '2024-07-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (587, 801, 9208.83, '2023-10-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (393, 970, 7906.16, '2020-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (151, 901, 9106.06, '2022-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (469, 899, 5775.17, '2021-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (169, 984, 2446.73, '2023-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (613, 486, 8605.22, '2022-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (388, 140, 7708.38, '2021-05-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (631, 61, 6572.69, '2022-06-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (191, 696, 8329.22, '2024-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (741, 254, 8938.59, '2021-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (570, 417, 2954.06, '2021-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (732, 507, 7117.33, '2020-11-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (244, 724, 4765.32, '2024-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (467, 680, 1964.5, '2023-09-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (859, 513, 1158.51, '2022-08-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (922, 725, 5184.26, '2021-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (161, 886, 3537.17, '2022-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (704, 864, 8049.72, '2021-07-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (473, 873, 9382.27, '2022-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (753, 63, 2129.21, '2024-09-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (58, 127, 964.31, '2020-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (995, 358, 2839.65, '2023-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (430, 3, 7933.58, '2023-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (875, 322, 2174.99, '2020-03-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (746, 698, 708.87, '2024-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (147, 88, 4216.83, '2021-06-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (239, 809, 9208.04, '2023-01-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (757, 678, 1212.81, '2024-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (521, 200, 4860.0, '2024-01-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (771, 372, 9754.51, '2024-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (734, 536, 1974.52, '2022-08-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (18, 975, 4663.43, '2023-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (390, 238, 6670.25, '2022-11-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (990, 72, 9669.15, '2025-02-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (256, 799, 9112.54, '2024-02-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (711, 705, 8828.83, '2021-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (337, 673, 6079.21, '2021-06-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (116, 636, 5697.29, '2025-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (604, 985, 5170.85, '2024-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (182, 882, 5396.35, '2024-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (590, 743, 3003.79, '2023-09-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (52, 207, 7263.5, '2021-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (211, 505, 4869.01, '2023-08-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 223, 5810.06, '2024-01-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (257, 133, 9266.58, '2023-01-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (110, 1000, 421.51, '2022-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (445, 580, 4727.1, '2023-10-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (284, 652, 263.06, '2020-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (568, 865, 9780.83, '2022-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (257, 89, 9264.83, '2020-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (40, 455, 7068.73, '2020-05-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (585, 330, 7466.52, '2023-08-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (42, 190, 6495.9, '2021-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (518, 918, 5977.61, '2023-04-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (942, 542, 5376.22, '2023-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (902, 957, 7955.82, '2020-05-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (188, 981, 6451.23, '2023-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (310, 880, 6291.69, '2024-05-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (16, 172, 5716.98, '2021-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (327, 166, 933.17, '2021-03-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (269, 366, 6315.18, '2024-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (90, 947, 6409.62, '2024-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (169, 739, 9328.85, '2020-11-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (358, 809, 6417.59, '2020-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (348, 414, 6861.79, '2022-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (420, 3, 1679.17, '2020-05-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (879, 3, 5555.91, '2021-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (995, 324, 5707.51, '2025-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (735, 909, 937.0, '2022-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (106, 663, 8972.24, '2025-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (457, 176, 6997.85, '2024-03-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (898, 798, 4802.16, '2022-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (715, 363, 6751.28, '2023-08-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (758, 139, 1291.95, '2024-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (136, 462, 2809.67, '2021-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (577, 983, 1275.61, '2020-07-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (194, 446, 4222.47, '2022-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (305, 116, 5814.34, '2021-05-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (499, 530, 4850.01, '2021-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (181, 251, 3620.69, '2022-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (117, 541, 5467.55, '2023-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (921, 272, 6189.88, '2024-04-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (958, 457, 1889.62, '2021-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (691, 246, 1744.99, '2024-05-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (820, 364, 4706.64, '2023-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (727, 943, 7869.0, '2023-12-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (189, 930, 5958.3, '2022-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (693, 352, 53.22, '2021-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (763, 595, 5802.21, '2023-08-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (462, 19, 2521.69, '2023-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (449, 578, 5310.84, '2024-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (306, 344, 7090.76, '2024-04-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (769, 817, 7348.97, '2020-12-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (977, 476, 9311.23, '2020-06-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (741, 551, 6310.41, '2022-01-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (936, 584, 4832.53, '2022-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (798, 67, 4251.57, '2025-02-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (750, 818, 6380.72, '2024-02-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (888, 408, 4846.99, '2024-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (412, 465, 4990.24, '2023-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (686, 904, 4511.65, '2022-03-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (370, 990, 6204.03, '2023-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (48, 264, 394.37, '2021-05-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (844, 483, 7125.15, '2023-08-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (847, 739, 660.42, '2023-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (533, 140, 8214.49, '2023-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (731, 977, 419.21, '2020-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (658, 348, 7355.85, '2021-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (84, 858, 1850.6, '2021-11-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (414, 451, 8161.55, '2023-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (485, 17, 2468.3, '2024-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (663, 855, 4410.3, '2022-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (962, 609, 1188.43, '2021-09-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (217, 559, 3461.89, '2022-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (63, 680, 1779.33, '2024-11-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (228, 183, 3377.36, '2025-02-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (793, 804, 7315.02, '2021-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (727, 139, 9648.38, '2023-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (28, 113, 7642.95, '2022-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (995, 364, 6263.59, '2023-08-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (443, 803, 7222.22, '2023-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (368, 160, 7227.76, '2024-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (674, 405, 2538.94, '2020-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (342, 746, 509.78, '2020-06-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (24, 815, 7498.79, '2023-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (665, 978, 7527.42, '2023-11-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (644, 992, 162.59, '2021-09-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (371, 317, 1952.33, '2021-05-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (3, 221, 4705.17, '2021-12-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (840, 935, 5143.6, '2022-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (723, 395, 9819.51, '2020-08-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (10, 651, 611.92, '2020-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (940, 162, 4744.78, '2023-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (878, 408, 8474.07, '2022-11-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (750, 405, 3262.79, '2022-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (271, 405, 3306.03, '2023-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (192, 60, 1707.21, '2020-03-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (810, 294, 9799.67, '2023-09-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (677, 219, 7061.86, '2021-12-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (863, 691, 3091.43, '2023-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (11, 362, 9231.06, '2020-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (865, 584, 1878.45, '2024-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (448, 50, 580.85, '2023-07-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (261, 369, 4927.18, '2024-08-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (617, 567, 8240.89, '2020-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (775, 488, 9513.78, '2022-08-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (987, 233, 9704.56, '2024-11-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (212, 435, 5890.47, '2021-10-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (780, 703, 4981.74, '2020-04-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (257, 329, 6206.01, '2020-06-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (535, 307, 836.08, '2021-09-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (937, 667, 1295.65, '2021-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (885, 472, 3693.89, '2023-09-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (746, 127, 2566.27, '2024-07-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (943, 462, 8019.79, '2024-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (422, 999, 4347.12, '2020-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (724, 536, 8530.74, '2020-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (225, 570, 7996.87, '2021-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (866, 249, 7499.68, '2022-06-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (468, 127, 6539.75, '2021-03-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (129, 31, 216.03, '2022-10-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (381, 930, 1923.03, '2021-02-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (230, 248, 4509.55, '2021-01-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 764, 8919.41, '2022-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (270, 32, 5382.3, '2024-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (962, 406, 8437.36, '2024-02-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (798, 134, 8112.65, '2022-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (760, 333, 276.67, '2023-01-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (366, 330, 8881.16, '2021-08-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (911, 374, 9485.12, '2022-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (294, 625, 1955.57, '2021-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (988, 963, 3239.49, '2021-09-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (268, 307, 6323.64, '2022-05-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (297, 389, 4181.07, '2023-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (77, 521, 7226.62, '2023-08-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (396, 961, 9853.54, '2021-11-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (306, 627, 5714.85, '2022-11-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (758, 856, 9540.29, '2024-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 211, 5795.75, '2023-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (91, 408, 7697.89, '2020-04-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (814, 175, 2797.16, '2021-08-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (528, 90, 5814.3, '2024-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (365, 58, 3270.54, '2022-01-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (649, 100, 4045.35, '2023-07-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (928, 417, 1104.29, '2021-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (904, 876, 4546.5, '2025-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (517, 702, 2103.29, '2022-05-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (84, 690, 3531.02, '2022-03-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (230, 181, 3784.34, '2020-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (274, 684, 3802.82, '2023-12-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (51, 497, 942.65, '2020-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (885, 290, 9330.92, '2024-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (189, 134, 8565.09, '2021-11-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (844, 944, 4069.81, '2024-01-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (233, 542, 5808.41, '2024-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (380, 514, 2383.2, '2024-12-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (355, 289, 4343.59, '2024-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (271, 91, 8831.07, '2023-07-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (9, 908, 1319.64, '2024-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (826, 457, 3503.48, '2022-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (263, 396, 3081.1, '2024-06-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (420, 340, 6653.79, '2020-10-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (112, 634, 3207.41, '2022-06-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (21, 712, 6010.72, '2022-02-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (629, 264, 346.56, '2024-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (248, 832, 9639.39, '2024-10-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (893, 420, 5240.44, '2025-01-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (704, 526, 4348.03, '2023-03-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (421, 920, 1033.01, '2021-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (302, 280, 464.66, '2020-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (787, 836, 8305.83, '2022-05-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (95, 753, 1719.66, '2024-12-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (604, 17, 4832.56, '2021-09-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (618, 717, 4215.59, '2021-02-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (878, 967, 3026.66, '2020-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (355, 109, 5016.27, '2022-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (328, 630, 3199.45, '2021-10-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (304, 329, 2763.82, '2021-10-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (338, 629, 4769.67, '2021-07-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (134, 510, 1541.68, '2020-09-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (896, 813, 5691.65, '2023-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (45, 122, 1254.01, '2020-04-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (355, 846, 2387.19, '2023-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (162, 88, 909.24, '2023-03-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (413, 867, 8984.6, '2022-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (259, 264, 9888.52, '2024-10-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (541, 933, 5808.58, '2020-10-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (678, 14, 9363.78, '2020-07-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (959, 335, 6453.57, '2024-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (63, 968, 9612.91, '2021-08-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 468, 6589.04, '2021-01-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (212, 722, 8749.13, '2023-01-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (650, 518, 7264.9, '2023-12-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (143, 762, 621.5, '2025-01-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (234, 495, 6101.97, '2020-05-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (152, 961, 5176.53, '2021-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (392, 631, 3761.98, '2021-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 857, 7905.19, '2024-08-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (615, 655, 4716.96, '2024-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (555, 636, 1972.18, '2020-06-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (757, 833, 9777.8, '2024-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (208, 696, 9929.23, '2023-01-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (695, 129, 9570.52, '2025-02-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (998, 517, 6261.27, '2021-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (383, 447, 284.27, '2020-03-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (142, 819, 2081.99, '2022-05-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (100, 864, 7232.86, '2024-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (698, 540, 5386.03, '2020-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (614, 720, 2459.78, '2023-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (525, 14, 7666.95, '2023-09-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (756, 716, 6159.77, '2021-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (29, 199, 3753.41, '2023-06-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (132, 930, 8860.93, '2021-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (406, 250, 4733.16, '2020-07-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (466, 90, 5137.95, '2024-02-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (901, 824, 7428.26, '2024-11-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (169, 242, 5845.83, '2021-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (799, 705, 2953.13, '2021-01-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (952, 995, 3911.94, '2023-12-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (111, 491, 3354.68, '2024-02-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (188, 230, 6906.25, '2020-06-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (302, 283, 827.15, '2021-03-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (315, 428, 7630.89, '2024-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (653, 286, 4385.73, '2020-06-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (22, 556, 2871.13, '2023-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (956, 544, 6803.14, '2023-07-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 343, 9614.01, '2024-12-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (953, 126, 4038.94, '2020-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (180, 843, 3381.0, '2021-01-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (185, 723, 6764.27, '2022-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (841, 265, 3417.57, '2024-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (615, 45, 1046.96, '2024-08-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (108, 678, 422.27, '2021-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (251, 456, 8043.85, '2022-04-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (867, 64, 4361.92, '2023-05-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (298, 273, 4367.92, '2020-12-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (190, 64, 8513.02, '2023-06-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (602, 261, 28.69, '2022-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (71, 243, 8461.06, '2021-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (736, 25, 3823.49, '2023-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (416, 762, 5681.89, '2020-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (102, 291, 2801.21, '2022-12-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (383, 593, 5979.19, '2024-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (815, 350, 5042.42, '2020-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (159, 944, 556.83, '2021-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (69, 35, 7199.4, '2021-10-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (484, 396, 2077.54, '2024-10-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (107, 242, 5387.14, '2021-01-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (513, 64, 7576.39, '2024-12-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (578, 608, 2618.57, '2022-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (708, 229, 2945.67, '2021-11-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (642, 292, 3576.67, '2024-06-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (822, 944, 6088.06, '2023-07-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (644, 477, 4233.0, '2024-08-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (990, 94, 8584.06, '2023-08-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (109, 707, 6771.85, '2023-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (575, 68, 8214.25, '2020-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (348, 382, 774.75, '2020-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (973, 838, 2693.6, '2023-08-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (48, 122, 6925.29, '2020-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (997, 19, 3781.17, '2023-07-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (168, 638, 3762.88, '2020-07-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (619, 99, 2023.12, '2023-06-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (418, 7, 4813.55, '2023-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (610, 627, 8656.8, '2022-04-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (37, 663, 3236.19, '2021-12-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (200, 908, 195.14, '2023-01-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (726, 823, 1645.98, '2023-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (232, 475, 3230.32, '2020-09-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (494, 151, 6993.98, '2024-11-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (144, 858, 3409.52, '2023-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (775, 484, 6526.59, '2023-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (165, 853, 305.77, '2024-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (638, 955, 1272.84, '2020-03-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (32, 655, 7672.95, '2022-01-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (761, 48, 7178.22, '2021-02-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (102, 5, 6771.96, '2023-10-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (983, 458, 7630.51, '2023-05-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (70, 870, 2281.27, '2021-03-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (511, 661, 386.47, '2021-08-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (577, 154, 6607.77, '2024-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (187, 433, 5442.38, '2021-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (656, 48, 4058.12, '2024-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (715, 948, 6711.27, '2022-05-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (241, 889, 7654.43, '2022-02-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (139, 794, 4624.03, '2021-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (551, 928, 8002.88, '2024-11-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (787, 601, 4524.26, '2024-06-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (121, 593, 7798.48, '2022-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (242, 162, 5632.72, '2021-12-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (824, 966, 2556.91, '2025-02-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (199, 307, 8636.05, '2021-12-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (88, 908, 6896.81, '2020-06-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (689, 921, 8948.15, '2020-04-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (725, 705, 149.29, '2022-09-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (290, 510, 4695.65, '2021-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (971, 317, 7119.93, '2024-05-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (450, 652, 5468.44, '2024-01-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (130, 74, 146.9, '2021-07-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (724, 698, 6587.67, '2020-04-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (264, 743, 7632.1, '2024-06-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (470, 894, 4979.09, '2024-09-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (463, 316, 9723.47, '2022-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (82, 819, 6441.37, '2022-03-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (940, 155, 7163.53, '2020-11-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (74, 30, 1649.63, '2022-10-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (684, 960, 9274.66, '2024-02-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (491, 358, 7676.07, '2024-04-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (92, 90, 5211.02, '2024-09-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (997, 619, 4033.55, '2023-12-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (605, 358, 3220.94, '2020-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (482, 744, 9584.59, '2023-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (727, 211, 458.57, '2024-06-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (393, 975, 352.29, '2023-08-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (495, 609, 5636.21, '2022-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (62, 79, 622.77, '2022-12-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (129, 246, 7894.0, '2024-08-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (904, 610, 1517.71, '2021-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (460, 626, 4188.46, '2020-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (770, 31, 2015.63, '2023-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (576, 416, 793.44, '2022-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (941, 438, 7825.26, '2022-06-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (466, 217, 5222.57, '2022-03-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (819, 684, 1686.07, '2024-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (44, 656, 1670.95, '2024-06-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (650, 690, 3634.03, '2021-12-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (539, 689, 3808.41, '2021-07-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (442, 27, 2570.56, '2022-04-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (527, 480, 9498.7, '2023-12-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (806, 744, 9306.76, '2022-12-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (637, 602, 3905.07, '2021-03-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (43, 142, 174.05, '2021-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (64, 376, 8286.95, '2022-04-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (46, 357, 3629.42, '2020-11-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (919, 319, 9168.68, '2022-03-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (99, 930, 4222.46, '2022-11-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (632, 529, 9746.46, '2023-02-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (827, 933, 8552.37, '2022-06-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (749, 623, 4144.21, '2022-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (332, 826, 0.65, '2023-08-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (848, 59, 9462.7, '2021-07-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (511, 442, 6269.97, '2021-05-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (510, 823, 4114.26, '2024-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (690, 896, 588.26, '2024-10-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (376, 611, 5940.59, '2024-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (912, 312, 8945.75, '2022-07-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (170, 930, 9320.38, '2020-07-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (957, 521, 7573.65, '2020-10-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (254, 486, 3015.74, '2020-11-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (588, 817, 8014.29, '2020-05-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (765, 481, 1998.4, '2024-02-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (71, 798, 2501.9, '2021-03-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (43, 410, 1892.51, '2021-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (596, 718, 5673.43, '2023-12-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (281, 858, 1997.89, '2023-10-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (803, 781, 3838.94, '2020-08-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (81, 876, 2252.55, '2023-11-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (110, 999, 1068.41, '2020-12-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (616, 342, 5038.86, '2024-04-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (948, 274, 2576.37, '2021-03-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (827, 18, 8751.5, '2023-04-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (477, 754, 6814.74, '2022-07-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (320, 412, 5777.91, '2021-02-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (885, 238, 758.32, '2021-12-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (274, 67, 9709.03, '2021-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (427, 405, 7373.32, '2024-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (536, 778, 6480.05, '2023-06-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (995, 779, 8285.53, '2023-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (945, 712, 8661.14, '2021-06-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (430, 199, 7576.98, '2020-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (428, 989, 3132.77, '2024-09-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (532, 35, 5750.17, '2020-09-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (560, 91, 6817.77, '2025-01-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (254, 279, 7644.95, '2022-09-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (278, 640, 1013.29, '2022-07-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (538, 383, 3309.77, '2022-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (871, 903, 962.87, '2020-10-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 533, 4114.95, '2024-02-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (616, 260, 7181.09, '2023-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (248, 28, 632.31, '2022-11-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (875, 2, 4138.57, '2021-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (769, 590, 894.3, '2023-08-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (142, 167, 9211.72, '2021-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (412, 626, 7783.23, '2023-07-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (325, 803, 4322.79, '2022-06-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (745, 145, 667.55, '2021-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (712, 567, 5325.98, '2023-09-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (216, 421, 9832.2, '2025-01-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (472, 383, 8853.83, '2021-10-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (372, 444, 8343.57, '2025-01-20');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (928, 514, 4421.8, '2024-04-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (454, 769, 9209.65, '2020-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (66, 998, 4366.61, '2022-05-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (889, 828, 5057.76, '2022-11-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (803, 445, 4395.93, '2021-06-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (249, 116, 9175.6, '2021-05-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (948, 660, 1393.25, '2023-09-15');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (238, 864, 4055.85, '2021-03-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (691, 449, 2899.88, '2024-05-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (664, 824, 7470.21, '2022-02-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (966, 694, 1429.91, '2020-11-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (749, 940, 8014.86, '2021-05-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (39, 356, 9812.04, '2021-02-22');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (340, 636, 35.02, '2021-05-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (74, 116, 1430.78, '2020-04-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (569, 295, 3148.62, '2020-11-08');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (904, 776, 4971.66, '2022-11-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (909, 352, 1205.11, '2021-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (397, 373, 2800.9, '2021-10-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (780, 378, 5786.98, '2021-09-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (411, 878, 8416.8, '2023-07-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (286, 673, 8358.42, '2021-12-19');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (698, 735, 6693.36, '2022-08-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (630, 200, 4436.03, '2020-10-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (578, 779, 5335.17, '2020-12-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (352, 155, 9744.25, '2020-04-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (366, 174, 8598.73, '2020-07-05');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (998, 313, 1400.27, '2024-02-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (152, 106, 2238.47, '2023-03-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (416, 340, 5053.1, '2023-06-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (349, 110, 2043.92, '2023-04-24');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (241, 663, 6002.24, '2024-12-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (31, 971, 1492.08, '2022-12-14');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (383, 770, 3302.32, '2021-01-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (837, 29, 8734.83, '2023-07-27');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (682, 916, 648.32, '2024-03-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (639, 441, 8552.1, '2022-12-25');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (216, 982, 1246.68, '2022-11-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (232, 347, 5066.16, '2020-07-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (733, 666, 2908.74, '2024-01-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (813, 449, 785.83, '2024-12-23');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (391, 920, 5809.53, '2024-03-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (86, 524, 6630.38, '2024-03-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (362, 845, 4969.63, '2020-09-16');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (116, 716, 2280.6, '2023-09-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (811, 561, 4902.62, '2020-10-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (684, 139, 5882.95, '2023-06-07');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (963, 317, 5834.9, '2021-10-29');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (976, 888, 628.29, '2022-01-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (254, 137, 4841.47, '2020-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (389, 231, 3119.79, '2024-10-11');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (416, 557, 2150.34, '2024-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (471, 906, 5325.13, '2024-05-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (717, 194, 2498.88, '2022-04-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (275, 191, 9290.9, '2021-03-04');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (96, 320, 9938.78, '2021-12-17');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (234, 377, 8330.72, '2021-07-21');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (298, 843, 3741.97, '2023-11-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (352, 719, 7856.2, '2024-11-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (856, 514, 9171.59, '2022-10-28');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (740, 498, 4324.89, '2024-09-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (166, 397, 1976.11, '2025-02-12');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (680, 287, 9540.17, '2020-05-18');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (787, 799, 3930.32, '2023-09-02');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (735, 676, 1935.44, '2025-03-09');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (563, 65, 3435.22, '2023-12-03');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (390, 261, 3120.27, '2024-10-06');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (631, 155, 6836.41, '2023-04-30');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (157, 128, 3463.47, '2024-07-13');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (333, 701, 5337.14, '2024-08-01');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (817, 980, 579.87, '2024-12-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (716, 405, 3624.43, '2023-01-31');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (774, 572, 9437.06, '2024-09-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (96, 789, 2436.88, '2023-05-10');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (855, 805, 1467.34, '2022-03-26');
INSERT INTO Przelewy (id_konta_nadawcy, id_konta_odbiorcy, kwota, data_przelewu) VALUES (703, 284, 7382.9, '2021-07-01');



/*updaty*/
	/*zmiana numeru cvv*/
		UPDATE karty SET cvv = 210 WHERE numer_karty = '1423019896438920';
		UPDATE karty SET cvv = 423 WHERE numer_karty = '3946007320197863';
		UPDATE karty SET cvv = 921 WHERE numer_karty = '8234879182521184';
		UPDATE karty SET cvv = 515 WHERE numer_karty = '9806647032121089';
	/*zmiana stanowiska*/ 
		UPDATE pracownicy SET stanowisko = 'Menedżer' , pensja = 9000.00 WHERE imie = 'Piotr' AND nazwisko = 'Nowak';
		UPDATE pracownicy SET stanowisko = 'Menedżer' , pensja = 4000.00 WHERE imie = 'Ewa' AND nazwisko = 'Kowalczyk';
	/*zmiana nazwiska*/
		UPDATE pracownicy SET nazwisko = 'Zielińska-Nowaczyk' WHERE imie = 'Katarzyna' AND nazwisko = 'Zielińska';
	/*podwyżka*/
		UPDATE pracownicy SET pensja = pensja + 10.00 WHERE pensja < 4000.00 ;


/*delete*/
	
		DELETE FROM klienci_pracownicy WHERE klienci_pracownicy.id_klienta = 18 AND klienci_pracownicy.id_pracownika = 4;
		
		DELETE FROM klienci_pracownicy WHERE klienci_pracownicy.id_klienta = 58 AND klienci_pracownicy.id_pracownika = 17;
		
		DELETE FROM klienci_pracownicy WHERE klienci_pracownicy.id_klienta = 20 AND klienci_pracownicy.id_pracownika = 200;
		
		INSERT IGNORE INTO klienci_pracownicy (id_klienta, id_pracownika)
		VALUES (18, 2), (58, 18), (20, 199);
	



/*kwerendy*/
	SELECT k.imie, k.nazwisko, p.imie, p.nazwisko, b.nazwa_banku FROM klienci k 
	JOIN klienci_pracownicy kp ON kp.id_klienta = k.id_klienta
	JOIN pracownicy p ON kp.id_pracownika = p.id_pracownika 
	JOIN banki b ON p.id_banku = b.id_banku;
	
	/*widoki*/
			
	CREATE VIEW Klienci_Aktywni AS
	SELECT 
	    k.id_klienta,
	    k.imie,
	    k.nazwisko,
	    COUNT(DISTINCT ka.id_karty) AS liczba_kart,
	    IFNULL(SUM(p.kwota), 0) AS laczna_kwota_przelewow
	FROM Klienci k
	LEFT JOIN konta ko ON k.id_klienta = ko.id_klienta
	LEFT JOIN karty ka ON ko.id_konta = ka.id_konta
	LEFT JOIN Przelewy p ON ko.id_konta = p.id_konta_nadawcy
	GROUP BY k.id_klienta, k.imie, k.nazwisko
	HAVING COUNT(DISTINCT ka.id_karty) >= 2 OR IFNULL(SUM(p.kwota), 0) > 5000
	ORDER BY laczna_kwota_przelewow desc;
	
	
	
	CREATE VIEW Banki_i_Pracownicy AS
	SELECT 
	    b.nazwa_banku,
	    COUNT(DISTINCT p.id_pracownika) AS liczba_pracownikow,
	    ROUND(AVG(p.pensja), 2) AS srednia_pensja_pracownika,
	    CASE 
	        WHEN b.otwarte_codziennie = 1 THEN 'Codziennie'
	        ELSE 'Nie codziennie'
	    END AS status_otwarcia,
	    CONCAT(TIME(b.czas_otwarcia), ' - ', TIME(b.czas_zamkniecia)) AS godziny_otwarcia
	FROM banki b
	LEFT JOIN pracownicy p ON b.id_banku = p.id_banku
	GROUP BY b.id_banku, b.nazwa_banku, b.otwarte_codziennie, b.czas_otwarcia, b.czas_zamkniecia
	HAVING liczba_pracownikow >= 1 OR srednia_pensja_pracownika > 5000
	ORDER BY srednia_pensja_pracownika DESC;
	




-- Tworzenie ról
CREATE ROLE 'rola_kierownik';
CREATE ROLE 'rola_kasjer';
CREATE ROLE 'rola_opieun_klienta';
CREATE ROLE 'rola_menedzer';

GRANT ALL PRIVILEGES ON bank_nowy.* TO rola_kierownik;
GRANT SELECT ON Klienci_Aktywni TO rola_kierownik;
GRANT SELECT ON Banki_i_Pracownicy TO rola_kierownik;


GRANT SELECT, UPDATE ON bank_nowy.* TO rola_menedzer;
GRANT SELECT ON Klienci_Aktywni TO rola_menedzer;
GRANT SELECT ON Banki_i_Pracownicy TO rola_menedzer;


GRANT SELECT ON bank_nowy.Klienci TO rola_kasjer;

GRANT SELECT, UPDATE ON bank_nowy.Klienci TO rola_opieun_klienta;
GRANT SELECT, UPDATE ON bank_nowy.Konta TO rola_opieun_klienta;
GRANT SELECT, UPDATE ON bank_nowy.profil_internetowy TO rola_opieun_klienta;
GRANT SELECT ON Klienci_Aktywni TO rola_opieun_klienta;


CREATE USER 'uzytkownik_kierownik'@'localhost' IDENTIFIED BY 'haslo';
CREATE USER 'uzytkownik_kasjer'@'localhost' IDENTIFIED BY 'haslo';
CREATE USER 'uzytkownik_menedzer'@'localhost' IDENTIFIED BY 'haslo';
CREATE USER 'uzytkownik_opiekun'@'localhost' IDENTIFIED BY 'haslo';

GRANT rola_kierownik TO 'uzytkownik_kierownik'@'localhost';
GRANT rola_kasjer TO 'uzytkownik_kasjer'@'localhost';
GRANT rola_menedzer TO 'uzytkownik_menedzer'@'localhost';
GRANT rola_opieun_klienta TO 'uzytkownik_opiekun'@'localhost';


SHOW GRANTS FOR 'rola_kierownik';


		
/*kwerenda 1*/
SELECT banki.nazwa_banku, count(klienci_pracownicy.id_klienta) AS 'ilość klientów', 
count(distinct klienci_pracownicy.id_pracownika) AS 'ilość pracowników'
FROM klienci_pracownicy
JOIN pracownicy ON klienci_pracownicy.id_pracownika = pracownicy.id_pracownika
JOIN banki ON pracownicy.id_banku = banki.id_banku
GROUP BY banki.id_banku;

/*kwerenda 2*/

SELECT konta.saldo, klienci.imie, klienci.nazwisko FROM klienci
JOIN konta ON klienci.id_klienta = konta.id_klienta
ORDER BY konta.saldo DESC
LIMIT 3;

/*kwerenda 3*/

SELECT banki.nazwa_banku AS 'Nazwa banku', SUM(konta.saldo) AS 'Suma pieniędzy klientów' from klienci
JOIN konta ON klienci.id_klienta = konta.id_klienta
JOIN klienci_pracownicy ON klienci_pracownicy.id_klienta = klienci.id_klienta
JOIN pracownicy ON klienci_pracownicy.id_pracownika = pracownicy.id_pracownika
JOIN banki ON pracownicy.id_banku = banki.id_banku
GROUP BY  banki.nazwa_banku;




/*kwerenda 4*/
SELECT CONCAT("Klient o najkrótszym loginie: ",  left(klienci.imie, 1), '. ', nazwisko) AS ' ', LENGTH(login) AS "długość loginu" FROM profil_internetowy
JOIN klienci ON profil_internetowy.id_klienta = klienci.id_klienta
WHERE
length(profil_internetowy.login) = (SELECT min(LENGTH(login)) FROM profil_internetowy)

UNION all
(
SELECT CONCAT("Klient o nadłuższym loginie: ",  left(klienci.imie, 1), '. ', nazwisko) AS ' ', LENGTH(login) AS "długość loginu" FROM profil_internetowy
JOIN klienci ON profil_internetowy.id_klienta = klienci.id_klienta
WHERE
length(profil_internetowy.login) = (SELECT max(LENGTH(login)) FROM profil_internetowy)
LIMIT 1
);


/*kwerenda 5*/

SELECT banki.nazwa_banku, ROUND(AVG(przelewy.kwota), 2) AS 'Średnia kwota przelewów'
FROM przelewy
JOIN konta AS nadawcy ON przelewy.id_konta_nadawcy = nadawcy.id_konta
JOIN klienci ON nadawcy.id_klienta = klienci.id_klienta
JOIN klienci_pracownicy ON klienci.id_klienta = klienci_pracownicy.id_klienta
JOIN pracownicy ON klienci_pracownicy.id_pracownika = pracownicy.id_pracownika
JOIN banki ON pracownicy.id_banku = banki.id_banku
GROUP BY banki.id_banku;


/*kwerenda 5*/



SELECT banki.nazwa_banku, pracownicy.imie, pracownicy.nazwisko, pracownicy.stanowisko, MAX(pracownicy.pensja) AS najwyzsza_pensja
FROM pracownicy
JOIN banki ON pracownicy.id_banku = banki.id_banku
GROUP BY banki.id_banku
ORDER BY banki.nazwa_banku, najwyzsza_pensja DESC;


/*kwerenda 6*/


SELECT klienci.imie, klienci.nazwisko, MAX(przelewy.kwota) AS najwyzszy_przelew
FROM klienci
JOIN konta ON klienci.id_klienta = konta.id_klienta
JOIN przelewy ON konta.id_konta = przelewy.id_konta_nadawcy
GROUP BY klienci.id_klienta
ORDER BY najwyzszy_przelew DESC
LIMIT 5;


/*kwerenda 7*/
SELECT lokalizacje.miasto AS 'Miasto', 
       COUNT(DISTINCT banki.id_banku) AS 'Liczba banków',
       COUNT(DISTINCT klienci.id_klienta) AS 'Liczba klientów'
FROM lokalizacje
JOIN banki_lokalizacje ON lokalizacje.id_lokalizacji = banki_lokalizacje.id_lokalizacji
JOIN banki ON banki_lokalizacje.id_banku = banki.id_banku
JOIN pracownicy ON banki.id_banku = pracownicy.id_banku
JOIN klienci_pracownicy ON pracownicy.id_pracownika = klienci_pracownicy.id_pracownika
JOIN klienci ON klienci_pracownicy.id_klienta = klienci.id_klienta
GROUP BY lokalizacje.miasto
ORDER BY 3 DESC;

/*kwerenda 8*/


SELECT klienci.imie AS 'Imię klienta' , klienci.nazwisko 'Nazwisko klienta', karty.numer_karty 'Numer karty', karty.data_waznosci 'Data ważności'
FROM klienci
JOIN konta ON klienci.id_klienta = konta.id_klienta
JOIN karty ON konta.id_konta = karty.id_konta
WHERE karty.data_waznosci BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 24 MONTH)
ORDER BY karty.data_waznosci ASC;


/*kwerenda 9*/


SELECT klienci.imie, klienci.nazwisko
FROM klienci
LEFT JOIN konta ON klienci.id_klienta = konta.id_klienta
LEFT JOIN karty ON konta.id_konta = karty.id_konta
WHERE karty.id_karty IS NULL
ORDER BY klienci.nazwisko, klienci.imie;



/*kwerenda 10*/

SELECT lokalizacje.miasto, COUNT(transakcje.id_transakcji) AS 'Liczba dokonanych wpłat'
FROM klienci
JOIN konta ON klienci.id_klienta = konta.id_klienta
JOIN transakcje ON konta.id_konta = transakcje.id_konta
JOIN klienci_pracownicy ON klienci.id_klienta = klienci_pracownicy.id_klienta
JOIN pracownicy ON klienci_pracownicy.id_pracownika = pracownicy.id_pracownika
JOIN banki ON pracownicy.id_banku = banki.id_banku
JOIN banki_lokalizacje ON banki.id_banku = banki_lokalizacje.id_banku
JOIN lokalizacje ON banki_lokalizacje.id_lokalizacji = lokalizacje.id_lokalizacji
WHERE transakcje.typ = 'wpłata'
GROUP BY lokalizacje.miasto
ORDER BY 2 DESC;

