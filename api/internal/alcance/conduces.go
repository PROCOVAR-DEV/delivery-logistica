package alcance

// LA PUERTA A LOS CONDUCES (00029, `docs/conduces.md`). Como en el resto de este paquete, es ESTE fichero
// quien rellena `sucursal`: un conduce no se junta, deshace ni lee fuera del alcance de quien llama.

import (
	"context"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// FilasParaConduce lee, CON CANDADO, las filas pedidas y —si se da `principal`— su principal y todos sus miembros.
// Solo dentro de `EnTx`: el candado dura lo que la transacción.
func (a *Acotado) FilasParaConduce(ctx context.Context, ids []uuid.UUID, principal *uuid.UUID) ([]sqlc.LeerFilasParaConduceRow, error) {
	return a.q.LeerFilasParaConduce(ctx, sqlc.LeerFilasParaConduceParams{
		Ids: ids, Principal: aPg(principal), Sucursal: a.sucursalPg(),
	})
}

// CrearConduce devuelve los que se juntaron; si son menos que los pedidos, el manejador deshace la transacción.
func (a *Acotado) CrearConduce(ctx context.Context, principal uuid.UUID, ids []uuid.UUID) ([]uuid.UUID, error) {
	return a.q.CrearConduce(ctx, sqlc.CrearConduceParams{
		PrincipalID: principal, Ids: ids, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) DeshacerConduce(ctx context.Context, principal uuid.UUID) ([]uuid.UUID, error) {
	return a.q.DeshacerConduce(ctx, sqlc.DeshacerConduceParams{PrincipalID: principal, Sucursal: a.sucursalPg()})
}

func (a *Acotado) SacarMiembroDeConduce(ctx context.Context, principal, id uuid.UUID) (int64, error) {
	return a.q.SacarMiembroDeConduce(ctx, sqlc.SacarMiembroDeConduceParams{
		ID: id, PrincipalID: principal, Sucursal: a.sucursalPg(),
	})
}

// MiembrosDeConduces: los miembros (no archivados) de varias principales, ya en el orden de lectura.
func (a *Acotado) MiembrosDeConduces(ctx context.Context, principales []uuid.UUID) ([]sqlc.MiembrosDeConducesRow, error) {
	if len(principales) == 0 {
		return nil, nil
	}
	return a.q.MiembrosDeConduces(ctx, sqlc.MiembrosDeConducesParams{
		PrincipalIds: principales, Sucursal: a.sucursalPg(),
	})
}
